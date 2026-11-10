# Databend Power BI Connector

Connect [Power BI Desktop](https://powerbi.microsoft.com/desktop/) to [Databend](https://databend.com) (Cloud or self-hosted) using the [HTTP API](https://docs.databend.com/developer/apis/http). No ODBC.

Pick one:

1. **Custom connector** — appears under Get Data as **Databend**
2. **Paste-in query** — no install; paste M into a blank query

---

## Host

Use a full URL with scheme.

| Environment | Example |
| --- | --- |
| Self-hosted | `http://127.0.0.1:8000` |
| Cloud | `https://tnxxxx.gw.us-east-2.default.databend.com` |

---

## Custom connector

### 1. Install

From the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-connector.ps1
```

This builds `powerbi/dist/DatabendConnector.mez` and installs it to:

`Documents\Microsoft Power BI Desktop\Custom Connectors\`

### 2. Allow the connector

In Power BI Desktop:

1. **File → Options and settings → Options → Security → Data Extensions**
2. Select **Allow any extension to load without validation**
3. Restart Power BI Desktop

### 3. Connect

**Get data → Databend**, then fill in:

| Field | Description |
| --- | --- |
| Host | Full URL (see above) |
| Database | Database name (e.g. `default`) |
| SQL Statement | Query to import |
| Warehouse | Cloud warehouse; leave blank when self-hosted |
| User / Password | Basic auth credentials |

---

## Paste-in query

No connector install. Uses built-in `Web.Contents` only.

1. **Get data → Blank query**
2. **Home → Advanced Editor**
3. Replace everything with [`powerbi/Databend.Query.pq`](powerbi/Databend.Query.pq)
4. Edit the CONFIG block (`Host`, `Database`, `Warehouse`, `Username`, `Password`, `SQL`)
5. **Done → Close & Apply**

For self-hosted, set `Warehouse` to `""`.

---

## Repository layout

```
install-connector.ps1              Build and install the .mez
powerbi/
  Databend.Query.pq                Paste-in query
  DatabendConnector/
    DatabendConnector.pq           Connector source
  dist/                            Built .mez (generated)
```

## License

[Apache License 2.0](LICENSE)
