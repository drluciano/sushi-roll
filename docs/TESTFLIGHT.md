# TestFlight setup (no Mac needed)

Everything below works in Safari on an iPhone or iPad.

1. **API key:** open App Store Connect, then Users and Access, Integrations, App Store Connect API, Team Keys. Generate a key with **Admin** access. Admin access lets CI create the distribution certificate for you. Download the `.p8` file (you only get one chance) and note the **Key ID** and **Issuer ID**.
2. **App ID:** on developer.apple.com, open Certificates, IDs & Profiles, then Identifiers, then +. Choose App IDs, then App. Pick an **Explicit** Bundle ID of `com.drluciano.sushiRoll`. No capabilities are needed.
3. **App record:** in App Store Connect, go to Apps, then +, then New App. Choose iOS, pick the bundle ID above, and give it any SKU.
4. **Team ID:** developer.apple.com, then Membership details.
5. **GitHub secrets:** in the repo, go to Settings, then Secrets and variables, then Actions, and add:
   - `APPLE_TEAM_ID`
   - `ASC_KEY_ID`
   - `ASC_ISSUER_ID`
   - `ASC_KEY_P8`: the whole text of the `.p8` file, including the `BEGIN`/`END` lines.

Then push to `main`, or run the **TestFlight** workflow from the Actions tab. Builds appear in TestFlight after Apple finishes processing them, usually in 5 to 15 minutes. The build number is the workflow run number.
