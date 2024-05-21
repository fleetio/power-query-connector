// This file contains your Data Connector logic
[Version = "1.0.0"]
section Fleetio;

BaseUrl = "https://secure.fleetio.com/api/";

SchemaTable = #table(
    {"Entity", "Type"}, {
        {"v2/contacts", ContactsType},
        {"v2/issues", IssuesType},
        {"v1/submitted_inspection_forms", SubmittedInspectionFormsType},
        {"v1/vehicles", VehiclesType},
        {"v1/expense_entries", ExpenseEntriesType},
        {"v1/parts", PartsType},
        {"v1/purchase_orders", PurchaseOrdersType},
        {"v1/vehicle_assignments", VehicleAssignmentsType},
        {"v2/service_entries", ServiceEntriesType},
        {"v1/fuel_entries", FuelEntriesType}
    }
);

GetSchemaForEntity = (entity as text) as type =>
    try SchemaTable{[Entity = entity]}[Type] otherwise error "Cannot find entiy: '" & entity * "'";

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
        entities = Table.SelectColumns(SchemaTable, {"Entity"}),
        rename = Table.RenameColumns(entities, ({"Entity", "Name"})),
        withData = Table.AddColumn(rename, "Data", each GetEntity(Uri.Combine(url, [Name]), [Name]), type table),
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
Fleetio.Feed = (url as text, api_endpoint, optional schema as type) as table => GetAllPagesByNextCursor(url, api_endpoint, schema);

GetEntity = (url as text, api_endpoint) as table =>
    let
        schema = GetSchemaForEntity(api_endpoint),
        result = Fleetio.Feed(url, api_endpoint, schema),
        appliedSchema = Table.ChangeType(result, schema)
    in
        appliedSchema;

/*
Function to get requests and pages from Fleetio

Args:
    url (text): the url endpoint for the Fleetio API path
    api_endpoint (text): the path
Returns:
    data (Table.FromRecords): resulting table from the given records in the request
*/
GetPage = (url as text, api_endpoint, optional schema as type) as table =>
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
        data = 
            if (schema = null) then
                Table.FromRecords(json[records])
            else
                let
                    // convert the list of records into a table (single column of records)
                    asTable = Table.FromList(json[records], Splitter.SplitByNothing(), {"Column1"}),
                    fields = Record.FieldNames(Type.RecordFields(Type.TableRow(schema))),
                    expanded = Table.ExpandRecordColumn(asTable, "Column1", fields)
                in
                    expanded
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
GetAllPagesByNextCursor = (url as text, api_endpoint, optional schema as type) as table =>
    Table.GenerateByPage(
        (previous) =>
            let
                nextCursor = if (previous = null) then url else Value.Metadata(previous) [start_cursor]?,
                page = if (nextCursor <> null) then GetPage(nextCursor, api_endpoint, schema) else null
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

// Schemas

ContactsType = type table [
    id = Int64.Type,
    archived_at = nullable text,
    email = nullable text,
    name = nullable text,
    first_name = nullable text,
    middle_name = nullable text,
    last_name = nullable text,
    group_id = nullable Int64.Type,
    group_name = nullable text,
    group_hierarchy = nullable text,
    technician = nullable text,
    vehicle_operator = nullable text,
    employee = nullable text,
    birth_date = nullable text,
    street_address = nullable text,
    street_address_line_2 = nullable text,
    city = nullable text,
    region = nullable text,
    postal_code = nullable text,
    county = nullable text,
    emplyee_number = nullable text,
    job_title = nullable text,
    license_class = nullable text,
    license_number = nullable text,
    license_state = nullable text,
    home_phone_number = nullable text,
    mobile_phone_number = nullable text,
    work_phone_number = nullable text,
    other_phone_number = nullable text,
    start_date = nullable text,
    leave_date = nullable text,
    hourly_labor_rate_cents = nullable Int64.Type,
    attachment_permissions = any,
    default_image_url = nullable text,
    account_membership_id = nullable text,
    custom_fields = any
];

IssuesType = type table [
    id = Int64.Type,
    number = nullable text,
    summary = text,
    description = nullable text,
    state = text,
    reported_at = nullable text,
    reported_by = any,
    resolvable_type = nullable text,
    resolved_at = nullable text,
    resolved_by = any,
    resolved_note = text,
    closed_at = nullable text,
    closed_by =  any,
    closed_note = text,
    due_date = nullable text,
    due_meter_value = nullable text,
    due_secondard_meter_value = nullable text,
    is_overdue = text,
    issue_priority = any,
    resolvable = any,
    creation_type = text,
    attached_permissions = any,
    asset = any,
    asset_type = text,
    submitted_inspection_form = any,
    fault = any,
    watchers_count = Int64.Type,
    comments_count = Int64.Type,
    images_count = Int64.Type,
    documents_count = Int64.Type,
    custom_fields = any,
    labels = any
];

SubmittedInspectionFormsType = type table [
    id = Int64.Type,
    started_at = text,
    submitted_at = text,
    date = text,
    failed_items = number,
    starting_lattitude = number,
    starting_longitude = number,
    submitted_lattitude = number,
    submitted_longitude = number,
    inspection_form = any,
    user = any,
    vehicle = any

];

VehiclesType = type table [
    id = Int64.Type,
    account_id = Int64.Type,
    archived_at = nullable text,
    fuel_type_id = nullable Int64.Type,
    fuel_type_name = nullable text,
    fuel_volume_units = text,
    group_id = nullable Int64.Type,
    group_name = nullable text,
    name = text,
    ownership = text,
    current_location_entry_id = nullable Int64.Type,
    system_of_measurement = text,
    vehicle_type_id = Int64.Type,
    vehicle_type_name = text,
    is_sample = text,
    vehicle_status_id = Int64.Type,
    vehicle_status_name = text,
    vehicle_status_color = nullable text,
    primary_meter_unit = nullable text,
    primary_meter_date = nullable text,
    primary_meter_usage_per_day = nullable text,
    secondary_meter_unit =  nullable text,
    secondary_meter_value = nullable text,
    secondary_meter_date = nullable text,
    secondary_meter_usage_per_day = nullable text,
    in_service_meter_value = nullable text,
    in_service_date = nullable text,
    out_of_service_meter_value = nullable text,
    out_of_service_date = nullable text,
    estimated_service_months = nullable Int64.Type,
    estimated_replacement_mileage = nullable text,
    estimated_resale_price_cents = nullable Int64.Type,
    fuel_entries_count = Int64.Type,
    service_entries_count = Int64.Type,
    service_reminders_count = Int64.Type,
    vehile_renewal_reminders_count = Int64.Type,
    comments_count = Int64.Type,
    documents_count = Int64.Type,
    images_count = Int64.Type,
    issues_count = Int64.Type,
    work_orders_count = Int64.Type,
    labels = any,
    group_ancestry = any,
    color = any,
    license_plate = any,
    vin = any,
    year = any,
    make = any,
    model = any,
    trim = any,
    registration_expiration_month = nullable Int64.Type,
    registration_state = any,
    default_image_url_small = any,
    external_ids = any,
    ai_enabled = text,
    assetable_type = text,
    custom_fields = any,
    axle_config_id = nullable Int64.Type
];

ExpenseEntriesType = type table [
    id = Int64.Type,
    created_at = any,
    updated_at = any,
    total_amount_cents = Int64.Type,
    notes = nullable text,
    expense_entry_type_id = Int64.Type,
    expense_entry_type_name = text,
    occured_at = text,
    vehicle_id = Int64.Type,
    vendor_id = nullable Int64.Type,
    custom_fields = any,
    vehicle = any,
    vendor = any
];

PartsType = type table [
    id = Int64.Type,
    description = nullable text,
    manufacturer_part_number = nullable text,
    measurement_unit_id = nullable Int64.Type,
    number = text,
    part_category_id = nullable Int64.Type,
    upc = nullable text,
    unit_cost_cents = nullable Int64.Type,
    average_unit_cost_cents = nullable text,
    default_image_url = nullable text,
    archived_at = nullable text,
    attachment_permissions = any,
    custom_fields = any,
    part_manufacturer = any,
    part_categrory = any
];

PurchaseOrdersType = type table [
    id = Int64.Type,
    number = Int64.Type,
    description = nullable text,
    state = nullable text,
    documents_count = Int64.Type,
    comments_count = Int64.Type,
    watchers_count = Int64.Type,
    discount_type = nullable text,
    tax_1_type = nullable text,
    tax_2_type = nullable text,
    submitted_for_approval_at = nullable text,
    rejected_at = nullable text,
    approved_at = nullable text,
    purchased_at = nullable text,
    received_partial_at = nullable text,
    received_full_at = nullable text,
    closed_at = nullable text,
    created_at = nullable text,
    updated_at = nullable text,
    discount_cents = nullable Int64.Type,
    tax_1_cents = nullable Int64.Type,
    tax_1_percentage = nullable text,
    tax_2_cents = nullable Int64.Type,
    tax_2_percentage = nullable text,
    subtotal_cents = nullable Int64.Type,
    shipping_cents = nullable Int64.Type,
    total_amount_cents = nullable Int64.Type,
    vendor_id = nullable Int64.Type,
    approved_by_id = nullable Int64.Type,
    created_by_id = nullable Int64.Type,
    closed_by_id = nullable Int64.Type,
    purchased_by_id = nullable Int64.Type,
    rejected_by_id = nullable Int64.Type,
    received_partial_by_id = nullable Int64.Type,
    recieved_fully_by_id = nullable Int64.Type,
    submitted_for_approval_by_id = nullable Int64.Type,
    purchase_order_status_id = nullable Int64.Type,
    part_location_id = nullable Int64.Type,
    custom_fields = any,
    labels = any,
    vendor = any
];

VehicleAssignmentsType = type table [
    id = Int64.Type,
    vehicle_id = Int64.Type,
    contact_id = Int64.Type,
    started_at = nullable text,
    ended_at = nullable text,
    current = text,
    future = text,
    starting_meter_entry_value = nullable number,
    ending_meter_entry_value = nullable number,
    comments_count = Int64.Type,
    attachment_permissions = any,
    contact = any,
    vehicle = any
];

ServiceEntriesType = type table [
    id = Int64.Type,
    completed_at = nullable text,
    reference = nullable text,
    started_at = nullable text,
    status = text,
    general_notes = nullable text,
    vehicle_id = Int64.Type,
    vendor_id = nullable Int64.Type,
    work_order_id = nullable Int64.Type,
    is_sample = text,
    primary_meter_entry = any,
    secondard_meter_entry = any,
    attachment_permissions = any,
    custom_fields = any,
    labels = any,
    vendor = any,
    vehicle = any,
    discount_type = nullable text,
    discount_percentage = nullable text,
    tax_1_type = nullable text,
    tax_1_percentage = nullable text,
    tax_2_type = nullable text,
    tax_2_percentage = nullable text,
    labor_subtotal_cents = number,
    parts_subtotal_cents = number,
    fees_cents = number,
    subtotal_cents = number,
    discount_cents = number,
    tax_1_cents = number,
    tax_2_cents = number,
    total_account_cents = number
];

FuelEntriesType = type table [
    id = Int64.Type,
    external_id = nullable text,
    fuel_type_id = nullable Int64.Type,
    vehicle_id = nullable Int64.Type,
    vendor_id = nullable Int64.Type,
    partial = text,
    personal = text,
    reference = nullable text,
    region = nullable text,
    reset = text,
    images_count = Int64.Type,
    documents_count = Int64.Type,
    comments_count = Int64.Type,
    watchers_count = Int64.Type,
    is_sample = text,
    date = text,
    created_at = text,
    updated_at = text,
    cost_per_hr = nullable text,
    cost_per_km = nullable text,
    cost_per_mi = nullable text,
    kpl = nullable text,
    uk_gallons = text,
    uk_gallons_per_hr = nullable text,
    us_gallons = text,
    us_gallons_per_hour = nullable text,
    liters = nullable text,
    liters_per_hr = nullable text,
    lp100k = nullable text,
    mpg_uk = nullable text,
    mpg_us = nullable text,
    price_per_volume_unit = nullable text,
    usage_in_hr = nullable text,
    usage_in_km = nullable text,
    usage_in_mi = nullable text,
    total_amount_cents = Int64.Type,
    attachment_permissions = any,
    custom_fields = any,
    vehicle = any,
    meter_entry = any,
    vendor = any
];

// Load common library functions
Extension.LoadFunction = (name as text) =>
    let
        binary = Extension.Contents(name), asText = Text.FromBinary(binary)
    in
        Expression.Evaluate(asText, #shared);

Table.ChangeType = Extension.LoadFunction("Table.ChangeType.pqm");
