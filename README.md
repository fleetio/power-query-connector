<h1 align="center">Fleetio Power Query Connector</h1>

<h3 align="center">
The Fleetio Power Query Connector allows you to connect directly to the Fleetio API, and pull data into various Microsoft Products such as Power BI
</h3>

</br>

## Install for Power BI Desktop

1. Download our **Fleetio.mez** file from this repo (located in `bin/AnyCPU/Debug`)
2. Open Power BI, and go to **File > Options and settings > Options > Security > Data Extensions**. Check the option **(Not Recommended) Allow any extension to load without validation or warning**
3. Restart Power BI Desktop
4. Go to **Get Data** and search fro **Fleetio(Beta)(Custom)**
5. After, simply follow the prompts from Power BI to get your data connected

## Run Locally

In order to run our connector locally, the best way to is run using the [Microsoft Power Query SDK](https://learn.microsoft.com/en-us/power-query/install-sdk)

1. Install the [Power Query SDK](https://learn.microsoft.com/en-us/power-query/install-sdk#installing-the-power-query-sdk) extension for VS Code
2. Clone this repo to your local machine, and open up VS Code with the repo
3. Although we have provided the pre-built .Mez file in this repo, it is best practice to rebuild it on your machine. To do so, simply in the VS Code command palette choose `build: Build connector project using MakePQX`
4. In order to connect your Fleetio Account, you must set your credentials. To do so, choose `Set Credential` option in the Power Query SDK menu in VS Code and follow the prompts in the command line
5. To test the connection, simply use the given `Fleetio.query.pq` file and select `Test` from the Power Query SDK menu in VS Code

## Current Schema

The current schema, or API endpoints, supported for this connector are as follows:

- `v2/issues`
- `v2/service_entries`
- `v1/submitted_inspection_forms`
- `v1/fuel_entries`
- `v1/vehicles`
- `v1/expense_entries`
- `v2/contacts`
- `v1/parts`
- `v1/purchase_orders`
- `v1/vehicle_assignments`

test
