let
    // CONFIG
    Host = "http://127.0.0.1:8000",
    Database = "default",
    Warehouse = "",
    Username = "databend",
    Password = "databend",
    SQL = "SELECT 1 AS n",
    // END CONFIG

    BaseUrl = Host,
    AuthHeader = "Basic " & Binary.ToText(Text.ToBinary(Username & ":" & Password), BinaryEncoding.Base64),
    BaseHeaders = [
        #"Authorization" = AuthHeader,
        #"Content-Type" = "application/json",
        #"Accept" = "application/json"
    ],
    Headers =
        if Warehouse = null or Warehouse = "" then
            BaseHeaders
        else
            Record.AddField(BaseHeaders, "X-DATABEND-WAREHOUSE", Warehouse),
    Body = Json.FromValue([
        sql = SQL,
        session = [database = Database],
        pagination = [wait_time_secs = 60, max_rows_per_page = 100000]
    ]),

    AssertOk = (json as record) as record =>
        let
            err = Record.FieldOrDefault(json, "error", null),
            state = Record.FieldOrDefault(json, "state", null)
        in
            if err <> null then
                error Error.Record("Databend.Error", Record.FieldOrDefault(err, "message", "Query failed"), err)
            else if state = "Failed" then
                error Error.Record("Databend.Error", "Query state=Failed", json)
            else
                json,

    GetUri = (relativeOrAbsolute as text) as record =>
        let
            absolute =
                if Text.StartsWith(relativeOrAbsolute, "http://") or Text.StartsWith(relativeOrAbsolute, "https://") then
                    relativeOrAbsolute
                else
                    BaseUrl & (if Text.StartsWith(relativeOrAbsolute, "/") then relativeOrAbsolute else "/" & relativeOrAbsolute),
            parts = Uri.Parts(absolute),
            portText =
                if parts[Port] = null then ""
                else if parts[Scheme] = "https" and parts[Port] = 443 then ""
                else if parts[Scheme] = "http" and parts[Port] = 80 then ""
                else ":" & Text.From(parts[Port]),
            root = parts[Scheme] & "://" & parts[Host] & portText,
            queryRecord = parts[Query],
            queryText =
                if queryRecord = null or Record.FieldCount(queryRecord) = 0 then ""
                else "?" & Uri.BuildQueryString(queryRecord),
            relativePath = parts[Path] & queryText,
            response = Web.Contents(root, [
                RelativePath = relativePath,
                Headers = Headers,
                ManualStatusHandling = {400, 401, 403, 404, 500, 502, 503}
            ])
        in
            AssertOk(Json.Document(response)),

    First = AssertOk(
        Json.Document(
            Web.Contents(BaseUrl, [
                RelativePath = "/v1/query",
                Headers = Headers,
                Content = Body,
                ManualStatusHandling = {400, 401, 403, 404, 500, 502, 503}
            ])
        )
    ),

    Pages = List.Generate(
        () => [page = First, stop = false],
        each not [stop],
        each
            let
                next = Record.FieldOrDefault([page], "next_uri", null)
            in
                if next = null or next = "" then
                    [page = [page], stop = true]
                else
                    [page = GetUri(next), stop = false],
        each [page]
    ),

    Schema = Record.FieldOrDefault(First, "schema", {}),
    ColumnNames = if Schema = null then {} else List.Transform(Schema, each _[name]),
    AllRows = List.Combine(
        List.Transform(Pages, each let d = Record.FieldOrDefault(_, "data", {}) in if d = null then {} else d)
    ),
    Cols =
        if List.IsEmpty(ColumnNames) then
            if List.IsEmpty(AllRows) then {} else List.Transform({0 .. List.Count(AllRows{0}) - 1}, each "Column" & Text.From(_ + 1))
        else
            ColumnNames,
    Result =
        if List.IsEmpty(AllRows) then
            #table(Cols, {})
        else
            Table.FromRecords(List.Transform(AllRows, each Record.FromList(_, Cols)))
in
    Result
