// Use this file to write queries to test your data connector
let
    result = Fleetio.Contents(),
    data = result{[Name = "v2/contacts"]}[Data],
    withRowCount = Table.AddIndexColumn(data, "Index")
in
    withRowCount
