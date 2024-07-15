# How to Contribute
While our Power Query Connector is still in review to become a certified connector in the Microsoft Ecosystem, we welcome anyone to help contribute to this project. By contributing, you also agree to our Code of Conduct.

## Creating an Issue
We use Issues in GitHub to track the following:
- Bugs
- Feature Requests
- [Security](SECURITY.md) (please refer to the Security section of this repo for more info)

Before you create a new issue:
1. Please make sure there is no open issue yet related to your question
2. Select the appropriate template related to your question

## Testing
We use the [Power Query SDK](https://learn.microsoft.com/en-us/power-query/power-query-sdk-vs-code) to run and test changes locally, please be sure to have the SDK downloaded if you plan on making changes

## Making Changes
In order to make changes to the repo, the following need to be done:
1. Make a Fork of the repo
2. After making the necessary changes, use the tests that come with the Power Query SDK to ensure the change compile correctly. We will also download and test your `.Mez` file that is submitted in the change request
3. Open an Issue, and be sure to link it to the PR description
4. Open the PR against our main branch, and a reviewer will be assigned

## General House Keeping
To keep our repository clean, we will adhere to the following:
1. Any Issue or PR that has not had any activity or response from the user that created or opened within 2 weeks will be closed out