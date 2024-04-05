// This file contains your Data Connector logic
[Version = "1.0.0"]
section Fleetio;

BaseUrl = "https://secure.fleetio.com/api/";

RootEntities = {
        "v2/issues",
        "v2/service_entries",
        "v1/submitted_inspection_forms",
        "v1/vehicles",
        "v1/expense_entries",
        "v2/contacts",
        "v1/parts",
        "v1/purchase_orders",
        "v1/vehicle_assignments"
    };

[DataSource.Kind="Fleetio", Publish="Fleetio.Publish"]
shared Fleetio.Contents = () => FleetioNavTable(BaseUrl) as table;

/*
Function to change requests from Fleetio into Nav Tables

Args:
    url (text): the url endpoint for the Fleetio API path
Returns:
    navTable (Table): resulting table
*/
FleetioNavTable = (url as text) as table =>
    let
        entitiesAsTable = Table.FromList(RootEntities, Splitter.SplitByNothing()),
        rename = Table.RenameColumns(entitiesAsTable, ({"Column1", "Name"})),
        withData = Table.AddColumn(rename, "Data", each Fleetio.Feed(Uri.Combine(url, [Name]), [Name]), Uri.Type),
        withItemKind = Table.AddColumn(withData, "ItemKind", each "Table", type text),
        withItemName = Table.AddColumn(withItemKind, "ItemName", each "Table", type text),
        withIsLeaf = Table.AddColumn(withItemName, "IsLeaf", each true, type logical),
        navTable = Table.ToNavigationTable(withIsLeaf, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable;
/*
Funtion to pass through the actual rest call to Fleetio

Args:
    url (text): the url endpoint for the Fleetio API path
    api_endpoint (text): the path
Returns:
    None
*/
Fleetio.Feed = (url as text, api_endpoint) as table => GetAllPagesByNextCursor(url, api_endpoint);

/*
Function to get requests and pages from Fleetio

Args:
    url (text): the url endpoint for the Fleetio API path
    api_endpoint (text): the path
Returns:
    data (Table.FromRecords): resulting table from the given records in the request
*/
GetPage = (url as text, api_endpoint) as table =>
    let
        account_token = Extension.CurrentCredential()[Username],
        api_token = Extension.CurrentCredential()[Password],
        headers = [
            #"Accept" = "application/json",
            #"Content-Type" = "application/json",
            #"X-Api-Version" = "2024-03-15",
            #"X-Client-Name" = "data_connector",
            #"X-Client-Platform" = "fleetio_power_query_connector",
            #"Authorization" = "Token " & api_token,
            #"Account-Token" = account_token
        ],
        source = Web.Contents(url, [ Headers = headers ]),
        json = Json.Document(source),
        nextCursor = GetNextCursor(json, Text.Combine({BaseUrl, api_endpoint})),
        data = Table.FromRecords(json[records])
    in
        data meta [start_cursor = nextCursor];

/*
Function to check if any more requests are needed. Is triggered by Table.GenerateByPage pass through function

Args:
    url (text): the url endpoint for the Fleetio API path
    api_endpoint (text): the path
Returns:
    page: the new page, if it exists
*/
GetAllPagesByNextCursor = (url as text, api_endpoint) as table =>
    Table.GenerateByPage(
        (previous) =>
            let
                nextCursor = if (previous = null) then url else Value.Metadata(previous) [start_cursor]?,
                page = if (nextCursor <> null) then GetPage(nextCursor, api_endpoint) else null
            in
                page
    );

/*
Function to check if there is a next_cursor from the request. If not return null

Args:
    response (json): response from the request
    url (text): api url
Returns:
    cursor: the full url with cursor if there is a next page, if not return null
*/
GetNextCursor = (response, url) as nullable text => 
    let
        // Check if there is a next cursor, if not we return null instead to break the iteration
        cursor = if(Record.FieldOrDefault(response, "next_cursor") <> null) then Text.Combine({url, "?start_cursor=", Record.FieldOrDefault(response, "next_cursor")}) else null
    in
        cursor;

/*
Changes a table object to a Navigation Table

Args:
    table
    keyColumns
    nameColumn
    dataColumn
    itemKindColumn
    itemNameColumn
    isLeafColumn
Returns:
    navigationTable
*/
Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta [
            NavigationTable.NameColumn = nameColumn,
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn,
            Preview.DelayColumn = itemNameColumn,
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;

/*
Calls GetAllPagesByNextCursor until all pages are gone
*/
Table.GenerateByPage = (getNextPage as function) as table =>
    let
        listOfPages = List.Generate(
            // get the first page of data
            () => getNextPage(null),
            // stop when the function returns null
            (lastPage) => lastPage <> null,
            // pass the previous page to the next function call
            (lastPage) => getNextPage(lastPage)
        ),
        // concatenate the pages together
        tableOfPages = Table.FromList(listOfPages, Splitter.SplitByNothing(), {"Column1"}),
        firstRow = tableOfPages{0} ?
    in
        // if we didn't get back any pages of data, return an empty table
        // otherwise set the table type based on the columns of the first page
        if (firstRow = null) then
            Table.FromRows({})
        else
            Value.ReplaceType(
                Table.ExpandTableColumn(tableOfPages, "Column1", Table.ColumnNames(firstRow[Column1])),
                Value.Type(firstRow[Column1])
            );

// Data Source Kind description
Fleetio = [
    Authentication = [
        // Key = [],
        // UsernamePassword = [],
        // Windows = [],
        UsernamePassword = [
            UsernameLabel = "account_token",
            PasswordLabel = "api_key",
            Label = "FleetioAuthentication"
        ]
    ]
];

// Data Source UI publishing description
Fleetio.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = Fleetio.Icons,
    SourceTypeImage = Fleetio.Icons
];

Fleetio.Icons = [
    Icon16 = { Extension.Contents("Fleetio16.png"), Extension.Contents("Fleetio20.png"), Extension.Contents("Fleetio24.png"), Extension.Contents("Fleetio32.png") },
    Icon32 = { Extension.Contents("Fleetio32.png"), Extension.Contents("Fleetio40.png"), Extension.Contents("Fleetio48.png"), Extension.Contents("Fleetio64.png") }
];
