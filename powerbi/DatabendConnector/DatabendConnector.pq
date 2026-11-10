section DatabendConnector;

[DataSource.Kind = "DatabendConnector", Publish = "DatabendConnector.Publish"]
shared DatabendConnector.Query = Value.ReplaceType(DatabendImpl.QueryExport, DatabendImpl.Type);

DatabendImpl.Type = type function (
    Host as (type text meta [
        Documentation.FieldCaption = "Host",
        Documentation.SampleValues = {"http://127.0.0.1:8000", "https://tnxxxx.gw.us-east-2.default.databend.com"}
    ]),
    Database as (type text meta [
        Documentation.FieldCaption = "Database",
        Documentation.SampleValues = {"default"}
    ]),
    Sql as (type text meta [
        Documentation.FieldCaption = "SQL Statement",
        Documentation.SampleValues = {"SELECT * FROM default.table"}
    ]),
    optional Warehouse as (type text meta [
        Documentation.FieldCaption = "Warehouse",
        Documentation.SampleValues = {"default_warehouse"}
    ])
) as table;

DatabendImpl.QueryExport = (
    Host as text,
    Database as text,
    Sql as text,
    optional Warehouse as text
) as table =>
    let
        baseUrl = Host,
        credential = Extension.CurrentCredential(),
        authHeader = "Basic " & Binary.ToText(
            Text.ToBinary(credential[Username] & ":" & credential[Password]),
            BinaryEncoding.Base64
        ),
        headers = DatabendImpl.Headers(authHeader, Warehouse),
        body = Json.FromValue([
            sql = Sql,
            session = [database = Database],
            pagination = [wait_time_secs = 60, max_rows_per_page = 100000]
        ]),
        first = DatabendImpl.PostQuery(baseUrl, headers, body),
        pages = DatabendImpl.CollectPages(baseUrl, headers, first),
        schema = if Record.HasFields(first, {"schema"}) and first[schema] <> null then first[schema] else {},
        columnNames = List.Transform(schema, each _[name]),
        allRows = List.Combine(
            List.Transform(pages, each if Record.HasFields(_, {"data"}) and _[data] <> null then _[data] else {})
        ),
        result = DatabendImpl.ToTable(columnNames, allRows),
        _cleanup = try DatabendImpl.GetRelative(baseUrl, headers, Record.FieldOrDefault(first, "final_uri", null)) otherwise null
    in
        result;

DatabendImpl.Headers = (authHeader as text, warehouse as nullable text) as record =>
    let
        baseHeaders = [
            #"Authorization" = authHeader,
            #"Content-Type" = "application/json",
            #"Accept" = "application/json"
        ]
    in
        if warehouse = null or warehouse = "" then
            baseHeaders
        else
            Record.AddField(baseHeaders, "X-DATABEND-WAREHOUSE", warehouse);

DatabendImpl.PostQuery = (baseUrl as text, headers as record, body as binary) as record =>
    DatabendImpl.AssertOk(
        Json.Document(
            Web.Contents(
                baseUrl,
                [
                    RelativePath = "/v1/query",
                    Headers = headers,
                    Content = body,
                    ManualStatusHandling = {400, 401, 403, 404, 500, 502, 503}
                ]
            )
        )
    );

DatabendImpl.GetRelative = (baseUrl as text, headers as record, relativeOrAbsolute as nullable text) as record =>
    let
        uri = relativeOrAbsolute,
        absolute =
            if uri = null or uri = "" then
                error Error.Record("Databend.Error", "Missing next_uri/final_uri")
            else if Text.StartsWith(uri, "http://") or Text.StartsWith(uri, "https://") then
                uri
            else
                baseUrl & (if Text.StartsWith(uri, "/") then uri else "/" & uri),
        parts = Uri.Parts(absolute),
        portText =
            if parts[Port] = null then
                ""
            else if parts[Scheme] = "https" and parts[Port] = 443 then
                ""
            else if parts[Scheme] = "http" and parts[Port] = 80 then
                ""
            else
                ":" & Text.From(parts[Port]),
        root = parts[Scheme] & "://" & parts[Host] & portText,
        queryRecord = parts[Query],
        queryText =
            if queryRecord = null or Record.FieldCount(queryRecord) = 0 then
                ""
            else
                "?" & Uri.BuildQueryString(queryRecord),
        relativePath = parts[Path] & queryText
    in
        DatabendImpl.AssertOk(
            Json.Document(
                Web.Contents(
                    root,
                    [
                        RelativePath = relativePath,
                        Headers = headers,
                        ManualStatusHandling = {400, 401, 403, 404, 500, 502, 503}
                    ]
                )
            )
        );

DatabendImpl.CollectPages = (baseUrl as text, headers as record, first as record) as list =>
    List.Generate(
        () => [page = first, stop = false],
        each not [stop],
        each
            let
                next = Record.FieldOrDefault([page], "next_uri", null)
            in
                if next = null or next = "" then
                    [page = [page], stop = true]
                else
                    [page = DatabendImpl.GetRelative(baseUrl, headers, next), stop = false],
        each [page]
    );

DatabendImpl.AssertOk = (json as record) as record =>
    let
        err = Record.FieldOrDefault(json, "error", null),
        state = Record.FieldOrDefault(json, "state", null)
    in
        if err <> null then
            error Error.Record(
                "Databend.Error",
                if Record.HasFields(err, {"message"}) then err[message] else "Query failed",
                err
            )
        else if state = "Failed" then
            error Error.Record("Databend.Error", "Query state=Failed", json)
        else
            json;

DatabendImpl.ToTable = (columnNames as list, rows as list) as table =>
    let
        cols =
            if List.IsEmpty(columnNames) then
                if List.IsEmpty(rows) then
                    {}
                else
                    List.Transform({0 .. List.Count(rows{0}) - 1}, each "Column" & Text.From(_ + 1))
            else
                columnNames,
        records = List.Transform(rows, each Record.FromList(_, cols))
    in
        if List.IsEmpty(records) then
            #table(cols, {})
        else
            Table.FromRecords(records);

DatabendConnector = [
    TestConnection = (dataSourcePath) => {
        "DatabendConnector.Query",
        dataSourcePath[Host],
        dataSourcePath[Database],
        "select 1"
    },
    Authentication = [
        UsernamePassword = [
            UsernameLabel = "User",
            PasswordLabel = "Password"
        ]
    ],
    Label = "Databend"
];

DatabendConnector.Publish = [
    Beta = false,
    Category = "Database",
    ButtonText = {"Databend", "Connect to Databend"},
    LearnMoreUrl = "https://docs.databend.com/developer/apis/http",
    SourceImage = DatabendConnector.Icons,
    SourceTypeImage = DatabendConnector.Icons
];

DatabendConnector.Icons = [
    Icon16 = {
        Extension.Contents("Databend16.png"),
        Extension.Contents("Databend20.png"),
        Extension.Contents("Databend24.png"),
        Extension.Contents("Databend32.png")
    },
    Icon32 = {
        Extension.Contents("Databend32.png"),
        Extension.Contents("Databend40.png"),
        Extension.Contents("Databend48.png"),
        Extension.Contents("Databend64.png")
    }
];
