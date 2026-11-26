# TickTick / 滴答清单 plugin

Shows tasks due today and overdue: the count beside the notch, the next three on Home, all of them
by list under the Plugins tab, and an alert 10 minutes before a timed task. Click a task to mark it
done.

## Install

Copy this folder to `~/Library/Application Support/Altools/Plugins/ticktick`
(or use **Settings › Notch › Plugins › Install examples**), switch it on, choose
dida365.com (滴答清单) or ticktick.com, and paste an access token.

## Getting an access token

TickTick's Open API uses OAuth. Once:

1. Sign in at <https://developer.dida365.com> (or <https://developer.ticktick.com>), choose
   **Manage Apps › New App**, and set the redirect URL to `http://localhost`.
2. Open this URL in a browser, with your app's client id:
   `https://dida365.com/oauth/authorize?scope=tasks:read%20tasks:write&client_id=CLIENT_ID&state=altools&redirect_uri=http://localhost&response_type=code`
   After you approve, the browser goes to `http://localhost/?code=CODE&state=altools`; copy `CODE`.
3. Exchange the code for a token in Terminal:
   ```sh
   curl -s -u CLIENT_ID:CLIENT_SECRET -d grant_type=authorization_code -d code=CODE \
     -d redirect_uri=http://localhost -d "scope=tasks:read tasks:write" https://dida365.com/oauth/token
   ```
   Paste the `access_token` from the reply into the plugin's settings. It's stored in your Keychain.

For ticktick.com, use `ticktick.com` instead of `dida365.com` in both URLs.

Needs `python3` (Apple's Command Line Tools: `xcode-select --install`).
