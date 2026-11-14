# Sign-up review: all 51 verified findings (14 Nov 2026)
Each finding was checked by two reviewers (`kept` = how many agreed). Source: web origin/main 675be73, agent 1f14100.

## 1. [landing] Landing never offers 'create a free account'; every button pushes download or sign-in, and the copy never mentions an account or that it is free
- Severity: high · kept 2/2 · owner: Finch · live site: yes · effort: 1-2 hours (copy + markup in AlternateHome and _Layout; re-run tools/screenshot-mocks check-landing.js, which has no CTA assertions today), then staging and Majid's go to swap
- Evidence: Views/Home/AlternateHome.cshtml:835 hero primary `<a class="btn btn-primary btn-lg" href="/Download">... Start on the Download page</a>`, :836 secondary `href="#how"`. :829-830 lead: 'Install one small app, sign in, and your computer becomes your private cloud.' :928-930 How it works: '1 Install Folderbird on your PC' / '2 Sign in from any browser' / '3 Access your files securely'. No account step. The only link to /Account/Register on the whole page is the nav at :814 (`<a class="fb-tool-link" href="/Account/Register">Register</a>`, plain), next to a solid 'Sign in' at :815. Below 1200px both are inside the burger. The bottom CTA band :1257 and the footer :1277 say 'Sign in or register' but link to /Account/Login. 'free' appears once on the page (:1225, the Android note). The free plan exists: Pricing.cshtml:66-69 'Sparrow ... $0 ... free forever ... 2 devices'. Same nav styling in Views/Shared/_Layout.cshtml:501-502.
- Impact: A first-time ad visitor learns the sequence 'download -> sign in' and never learns that an account is needed or that it costs nothing. The direct path to the money step (Register) is either invisible on phones or styled as the secondary nav item, and the 'register' CTAs land on a sign-in form. Overnight: 1 Register view, 0 sign-ups, and 3 installer downloads that went nowhere.
- Fix: For signed-out visitors: make the hero primary button 'Create your free account' -> /Account/Register and the secondary 'Download for Windows' -> /Download. Put one line under the buttons: 'Free for 2 PCs - no card needed.' Rewrite How-it-works step 1 as 'Create your free account', then 'Install the app on your PC and sign in', then 'Open folderbird.com anywhere'. Point the CTA-band and footer 'Sign in or register' links at /Account/Register (which already has 'Sign in' at Register.cshtml:63). In both navs (AlternateHome :814-815, _Layout :501-502), make 'Register' the solid button with the label 'Sign up free', and make 'Sign in' plain.
- Reviewer correction: Keep the hero, how-it-works and nav changes as proposed. When signed out: hero primary 'Create your free account' links to /Account/Register, the secondary 'Download for Windows' links to /Download, and the line 'Free for 2 PCs, no card needed' goes under the buttons. Both of those claims are verified: the default DeviceLimit is 2 and the Register form has no payment field. Make the steps 1 'Create your free account', 2 'Install the app on your PC and sign in', 3 'Open folderbird.com anywhere'. In both navs, make 'Sign up free' the solid button and 'Sign in' plain. The flow after registering already leads to the download: the empty /Device page links /Download at DeviceList.cshtml:445.

Change one part. At the CTA band (:1257) and the footer (:1277), do NOT repoint 'Sign in or register' to /Account/Register. That would send returning users to the sign-up form. Split it into two links instead: 'Sign up free' to /Account/Register and 'Sign in' to /Account/Login. Then add an assertion to tools/screenshot-mocks/check-landing.js that the signed-out hero primary links to /Account/Register, so a later edit cannot quietly undo it.

This is web code, so the owner is Finch. It changes the LIVE site after a staging check and Majid's go to swap. Effort is about 1-2 hours.

A related lower-priority item for Swift: the Windows app's LoginForm has no 'No account? Create one free' link to https://folderbird.com/Account/Register. That is the dead end for installers who skipped the web sign-up. It needs a signed release, so it takes hours plus a release cycle, and it does not change the live site until the fleet updates. | Keep the direction of the fix (Finch, live site after staging and Majid's go to swap, about 1-2 hours), with these changes:

(1) Wrap the new hero buttons in `@if (User.Identity?.IsAuthenticated != true)`. Signed-in visitors should keep a link to /Device or /Download. Today the hero buttons are not conditional at all.

(2) Hero buttons for signed-out visitors:
- Primary: 'Create your free account' -> /Account/Register.
- Secondary: 'Download for Windows' -> /Download.
- Keep 'See how it works' as a text link rather than dropping it.

Add one line under the buttons: 'Free for 2 PCs, no card needed'. Pricing.cshtml:69 says 2 devices, and registration asks for no payment.

(3) In the CTA band and the footer, split 'Sign in or register' into two links, Register first. Do not point both at Register.

(4) In the AlternateHome navs (:814-815) and _Layout (:501-502), make 'Sign up free' the solid button and 'Sign in' plain. On phones the nav sits behind the burger menu, so the hero button change is the part that matters there.

(5) Rewrite How it works as:
1. Create your free account
2. Install the app on your PC and sign in
3. Open folderbird.com anywhere

(6) Add a CTA assertion to tools/screenshot-mocks/check-landing.js: the signed-out hero links to /Account/Register.

Related gap, Swift's to fix: the Windows app's sign-in window offers no way to create an account. It shows only 'Connect this device to your account' and a 'Sign In' button (LoginForm.Designer.cs:77, :201, :252). Someone who installs without an account hits a dead end inside the app. That is the likelier leak for the 3 installer downloads. The fix is a 'No account? Create one free' link that opens https://folderbird.com/Account/Register. It reaches users only through the next signed release (1.2.8.1 or later), so it does not change the live site.

## 2. [landing] Windows app sign-in has no 'Create account' or 'Forgot password', and the installer ends without pointing at sign-up
- Severity: high · kept 2/2 · owner: Swift · live site: yes · effort: About 1 hour of code; the release is gated on Majid running publish-release.ps1 (signing + OTPs) and arming, about 1-2 hours of his time
- Evidence: folderbird-agent FileRouteClient/LoginForm.Designer.cs: the form's only texts are lblSubtitle 'Connect this device to your account' (:77), lblTitle (:89), Email (:119), Password (:142), 'Show password' (:164), 'Remember my email' (:177), btnLogin 'Sign In' (:201), lblFooter 'This device' (:223). There is no LinkLabel and no link to the website. LoginForm.cs:145 shows a non-existent account as 'Incorrect email or password. Please try again.' Installer (web repo tools/windows-installer/Folderbird.iss [Run]) has only `Filename: "{app}\{#AppExe}"; Description: "Start {#AppName} now"; Flags: nowait postinstall skipifsilent`.
- Impact: The landing and /Download send people to the installer first (finding above). Someone who installs without an account hits a sign-in wall with no way forward and an error that suggests they mistyped. This matches 3 ad visitors downloading the installer and 0 sign-ups.
- Fix: In LoginForm, add a 'No account? Create one free' LinkLabel under Sign In that opens https://folderbird.com/Account/Register. Add 'Forgot password?' opening /Account/ForgotPassword. When the server answers that the email has no account, say so and point to the link. In Folderbird.iss add a postinstall entry (checked by default) 'Create my free Folderbird account', opening https://folderbird.com/Account/Register with Flags: shellexec postinstall skipifsilent. This needs a new signed release (publish-release.ps1, which needs Majid's password plus OTPs) and the documented fleet-arming order.
- Reviewer correction: Swift (app) and the .iss owner (Swift or Finch; the file is in the web repo).

1. Keep the one generic LoginFailed answer. Do not add a server reply that says an account does not exist. Change the copy at LoginForm.cs:145 to something like "Incorrect email or password. No account yet? Create one free below." Add two LinkLabels under btnLogin:
   - "No account? Create one free" opens https://folderbird.com/Account/Register?from=app.
   - "Forgot password?" opens https://folderbird.com/Account/ForgotPassword.
   Open them with Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }) inside a try/catch, the way MyCustomApplicationContext.cs:610 already does. Build the URL from the app's configured base host, not a literal, so a staging or test-profile build does not send people to production.

2. In Folderbird.iss [Run], add a second postinstall entry, checked by default:
   `Filename: "https://folderbird.com/Account/Register?from=installer"; Description: "Create my free Folderbird account"; Flags: shellexec postinstall skipifsilent nowait`
   It runs unelevated (PrivilegesRequired=lowest), so the browser opens as the user.

The ?from= markers make the change measurable in the HTTP logs.

Release and effort: this changes the live download. It needs publish-release.ps1 (Majid's password plus three OTPs). For new users, what matters is moving the seven DownloadController constants together so /download/windows and /download/windows/setup serve the new build. Arming the fleet's auto-update is optional here, because existing installs already have accounts, and the installer change reaches only new installs anyway. Code is about 1 hour. Majid's part is about 1 hour (sign, publish, move the constants); arming would add more. | 1. **Windows app (Swift).** Under "Sign In" in LoginForm, add two LinkLabels:
   - "No account? Create one free", opening https://folderbird.com/Account/Register
   - "Forgot password?", opening https://folderbird.com/Account/ForgotPassword

   Open them with `Process.Start(new ProcessStartInfo(url){UseShellExecute=true})`, the pattern already used for `ms-settings:`. Build the URL from the host in `Utils._BASEURL`, so a test-profile copy opens its own server and not production. Keep the LoginFailed message generic: "Incorrect email or password. No account yet? Create one free below." Do NOT make the server tell the app that an email has no account.

   Optionally add the same register link to the status window (InfoForm) while signed out. That window is what a manual first launch shows.

2. **Installer (Finch).** In Folderbird.iss [Run], add:
   `Filename: "https://folderbird.com/Account/Register"; Description: "Create my free Folderbird account"; Flags: shellexec postinstall skipifsilent nowait`
   It is checked by default. Consider making it the first entry.

3. **Shipping.**
   - **Ship both together (recommended):** put the installer change in the next app release (1.2.8.2+). That release needs Majid's publish-release.ps1 run (password + OTPs), then the documented arming order, because WinBlob and the auto-update settings must move together.
   - **Ship the installer sooner, on its own:** that needs no fleet arming, only build-installer.ps1 (Majid's signing password + OTP) plus new SetupBlob/SetupSha256/SetupBytes in DownloadController (web: staging, then swap = live site). Caveat: build-installer.ps1 uploads `Folderbird-Setup-<Version>.exe` with `--overwrite true`. Rebuilding 1.2.8.1 would replace the published bytes under the same name, so the page's printed SHA-256 would not match the served file until the constants swap reaches production. Use a new file name, or ship it with the next version.

Effort: about 1 hour of code. Majid's time: about 30 minutes for an installer-only release, or 1-2 hours for a full app release with arming.

## 3. [landing] On phones the hero button sits 1.4-1.8 screens down; the first screen has no tappable action
- Severity: high · kept 2/2 · owner: Finch · live site: yes · effort: About 1 hour plus re-shooting/re-running the landing checks; staging, then Majid's go to swap
- Evidence: Measured (headless Chromium, signed out): at 390x844 the hero h1 is 158-297, the hero mock 319-880 (561px, aria-hidden decoration), the lead 902-1189, and the 'Start on the Download page' button 1215-1272. At 360x740 the button is at 1331. The page is about 14,000px tall at 390px. Cause: AlternateHome.cshtml:478-486 mobile ordering: `.hero-shot{order:3;...}`, `.hero p.lead{order:4;}`, `.hero-cta{order:5;}`. :479 `.hero-text{display:contents;}`. The lead :829-832 is 56 words.
- Impact: Meta traffic is phones inside the Facebook/Instagram in-app browser. Those visitors see a headline and a fake desktop file browser, with nothing to tap, and many leave before scrolling 1,200px. That fits about 111 landing hits producing 8 /Download and 1 /Register visit.
- Fix: In the max-width:980px block, set `.hero-cta{order:3}` so the buttons sit directly under the headline. Move the mock to order 5, or cap it to about 260px on phones, for example by hiding .hb-browsehead. Cut the lead to one sentence on phones, for example by wrapping the second half in a span that is hidden below 560px. Keep the 'free' line from the first finding next to the button.
- Reviewer correction: Owner Finch. The live site changes only after Majid's go to swap.

The fix direction is right, but the order values as written are incomplete. With `.hero-cta{order:3}` and the mock at 5, the Windows/Linux platform line (`.hero-plat`, order 6) and the long lead end up between the button and the mock. Use one consistent order in the max-width:980px block (AlternateHome.cshtml:480-486):
- `.hero .eyebrow{order:1}`
- `.hero h1{order:2}`
- `.hero-cta{order:3;margin-top:4px}`
- `.hero-plat{order:4;margin:12px 0 0}`
- `.hero-shot{order:5}`
- `.hero p.lead{order:6}`
- `.hero-proof{order:7}`

This keeps the visual high, which was the documented reason for the current order (:475-477), and puts the button directly under the headline. Optionally:
- shorten the lead on phones by wrapping its second and third sentences in a span hidden below 560px;
- cap the mock (for example, hide `.hb-browsehead` at 560px or below).

Verify at 360x740 with the cookie banner visible: the primary button's bottom edge must sit above the banner, at roughly 600px or less.

Also consider a phone-specific primary action. /Download on a phone offers a Windows installer the visitor cannot run. Either add "Create a free account" (href /Account/Register) as the primary button on touch devices, or label the button "Get it for your PC". Coordinate this with the "free" wording from the first finding.

No landing check asserts hero order. Run check-landing.js and check-secmenu.js. No screenshot re-shoot is needed: the landing captures do not include the hero.

Effort: about 1 hour, then staging, then Majid's go to swap. | Edit only inside the `@media(max-width:980px)` block (Views/Home/AlternateHome.cshtml, about :479-486):
1. Set `.hero-cta{order:3}`, so the buttons sit directly under the h1.
2. Set `.hero-shot{order:4}` and keep its existing margin.
3. Move the lead to order 5 and cut it to its first sentence on phones. Wrap the rest of :829-832 in a span that is hidden below 560px, so desktop copy is unchanged.
4. Keep `.hero-plat` and `.hero-proof` at 6 and 7.

Optionally cap the mock on phones (for example `.hero-shot .hb-browsehead{display:none}`, or a max-height with overflow hidden) to bring the next section closer. This is not needed once the CTA is above it.

Two refinements the finding missed:
(a) A phone visitor cannot install the Windows app, so "Start on the Download page" is a weak primary action on a phone. Consider making the phone's first button "Create a free account" (/Account/Register), with Download as the second, so the sign-up can happen on the phone and the install later on the PC. This is a copy decision; check it with Majid and Wren.
(b) The first-visit cookie banner covers the bottom of the first screen. Make sure the moved CTA ends up above it at 360x740. On that screen it would sit at about 415-472 px, which is clear of the banner.

After the change:
- Re-run `python3 render_landing.py`, `node check-landing.js` and `node check-secmenu.js`.
- Measure the button top at 360x740, 390x844 and 412x915, and expect it under about 450px.

This changes the live site only after a staging deploy and Majid's go to swap. Owner: Finch. Effort: about 30-60 minutes. No landing screenshots need re-shooting, because none of the captures show the landing hero.

## 4. [landing] Cookie banner covers the hero button on 1366x768 laptops and a quarter of phone screens
- Severity: medium · kept 2/2 · owner: Finch (Majid approves the shortened consent wording) · live site: yes · effort: 30-60 minutes; staging, then swap
- Evidence: Views/Shared/_CookieConsent.cshtml:19 `position:fixed; left:0; right:0; bottom:0; z-index:200001` with a 5-line notice (:21-25). Measured at 1366 wide (about 681px viewport): the banner spans 554-681 and the hero CTA 566-623 sits underneath it. Measured on phones: 190px tall at 390x844 (654-844), 211px at 360x740, 190px of a 664px in-app viewport. The banner shows for everyone with no choice saved (:37), which is every ad visitor.
- Impact: On the most common Windows laptop resolution, the one button on the page is hidden until the visitor deals with the consent box. On phones a quarter of the first screen is legal text. Both raise the chance of a bounce on the first screen, and the Ads/GA tag only loads after Accept.
- Fix: Make the banner compact: one short line, for example 'Cookies for analytics and ads - only if you accept. Privacy policy', with Reject and Accept on the same row and kept equal size. On phones, use a smaller font and padding (aim for 70-90px tall). Optionally pin it as a corner card on desktop so it cannot cover the hero buttons. The consent semantics do not change. The new wording is the consent notice, so Majid signs off the text.
- Reviewer correction: The proposed fix is not enough as written: a compact one-line full-width bar does not reliably clear the button. I simulated it (short sentence, 8px padding, about 45px tall). The primary button is still covered at 1366x640 and at 1366x657, and at 1366x620 and 1280x600 its centre is covered. Only at 1366x681 is it clear. Real viewports on 1366x768 laptops are about 620-660px, so the compact bar alone would often still cover the button.

So the corner card on desktop should be required, not optional, and it must sit bottom-RIGHT. At 1366 the call-to-action column is at x 77-592; the right half holds the hero screenshot, which is decorative (aria-hidden).

Suggested shape: at 700px and wider, use `left:auto; right:16px; bottom:16px; max-width:380px; border-radius:10px`, with one short sentence and Reject and Accept equal in size on one row. In a simulation this was about 106px tall at x 970-1350, and it left the button clickable at 1280x600 and at 1366x620, 640, 657 and 681.

Below 700px, keep a full-width bar but use the short sentence and smaller padding. I measured about 98px at 390x844 and 360x740, against 190-211px today.

Keep the consent behaviour as it is today: the same localStorage key, nothing loads before Accept, Reject stays as easy as Accept, and the footer 'Cookie settings' link stays. The shortened text is the consent notice, so Majid approves the wording. The /privacy section 6 wording may need the same check.

Trade-off to mention to Majid: a less intrusive card can lower the Accept rate. Fewer people would then carry the Ads tag, which matters while Google Ads is reporting 0 conversions.

The same partial is included by _Layout (line 1332), so the change also reaches /Download and /Account/Register; check those pages at 1366x650.

Owner: Finch for the code, Majid for the wording. It changes the live site, via staging and then a swap. Effort: about 1 hour including the 1366/1280/phone checks. | Owner: Finch builds it; Majid approves the shortened consent wording. Effort: about 1-2 hours including the check. Ship to staging first, then swap; it changes the live site.

1. **Desktop, 768 px wide and up:** make the banner a bottom-right card, about 360-400 px wide.
   - Keep it clear of the hero's left column, where the headline and buttons sit (x=77-592 at 1366). A bottom-left card would cover the CTA.
   - Keep it above the back-to-top button (fixed bottom-right, x=1304-1348, z-index 60) and clear of the section rail. The card will sit over the lower part of the hero screenshot, which is acceptable.
   - Keep the z-index above the navbar (1030), as today.

2. **Phones:** keep a full-width bottom bar, but compact: smaller font and padding, Reject and Accept on one row. Aim for 70-90 px instead of 190-211 px.

3. **Both sizes:**
   - Keep Reject and Accept the same size and weight.
   - Do not change the stored values or the gating. fb-consent stays 'granted' or 'denied', and fbLoadGtag / fbStopGtag stay as they are.
   - The short notice must still name the purposes: analytics, ad measurement, and showing our ads to past visitors. Keep the Privacy policy link and the "Cookie settings" re-open. For example: "Cookies for analytics and ads, including showing our ads to past visitors, only if you accept. Privacy policy". Majid signs off this text.

4. **Verify by measurement, with the banner present.**
   - Add a check that inlines _CookieConsent, or a flag in render_landing.py that keeps it.
   - At 1366x607, 1366x635, 1280x632 and 1440x789: the centre point of "Start on the Download page" must not be inside #cookieConsent.
   - At 390x664, 360x740 and 390x844: the banner must be 90 px tall or less.
   - The same partial renders on every _Layout page, including /Download and /Account/Register. Check that it covers no primary button there either.

## 5. [landing] Phone visitors are routed to a Windows installer; nothing tells them what to do from a phone
- Severity: medium · kept 2/2 · owner: Finch · live site: yes · effort: 1-3 hours (media-query version); the email-me-the-link variant is more
- Evidence: No device detection anywhere: grep of DownloadController.cs, HomeController.cs, Download/Index.cshtml and AlternateHome.cshtml finds no user-agent or mobile check. Landing hero platform line AlternateHome.cshtml:833 lists Windows and Linux beta only. The Android section starts about 11,300px down at 390px (measured, about 13 screens). On /Download, the phone's primary button is `<a class="dl-btn" id="fbHeroWin" href="@heroWin">Download for Windows</a>` (Download/Index.cshtml:159), then Linux (:160). The Google Play badge is a small translucent pill (:163-166). The only sign-up link is a text link in step 2 (:185). In an approximate render at 390px: Windows button about 569-625, Play badge about 712-762, step-2 register link about 1,408. In a 664px in-app viewport the cookie banner starts at about 470 and covers all three hero buttons. `.dl-hero{margin-top:56px}` (:35) adds 56px of empty space above the hero, on top of the body's 66px padding.
- Impact: About 5 Meta visits overnight, 3 of them from the in-app browser on phones. On a phone the useful things are creating the account now (to install on the PC later) and the Android app. The page offers neither prominently, and the obvious button downloads a file the phone cannot open.
- Fix: On phones (a CSS media query is enough; no user-agent sniffing needed), show a block at the top of the /Download hero and under the landing hero buttons: 'On your phone? Create your free account now - then open folderbird.com/download on your PC.' Give it a solid 'Create free account' button, and make 'Get it on Google Play' a full-size button. Move 'Download for Windows' below them on narrow screens. Drop the extra 56px top margin on phones. Optional later: an 'Email me the PC download link' form.
- Reviewer correction: Do this on /Download and the landing hero. It goes to staging on push and reaches production only after a swap.

1. **Phone block.** Add an "On your phone?" block, server-rendered but hidden by default. Show it with CSS only when both `(max-width:700px)` and `(hover:none) and (pointer:coarse)` match, so a narrow desktop window never sees it. Copy: "Create your free account now, then open folderbird.com/download on your computer." Give it a solid "Create free account" button linking to /Account/Register.
2. **Store button by OS.** Pick it with a few lines of progressive JS reading `navigator.userAgent`:
   - Android with `Android:PlayStoreUrl` set: a full-size "Get it on Google Play" button.
   - iPhone/iPad: no Play button; say "iPhone app coming soon - the website works on your phone today."
   - No JS or OS not recognised: show the account button only.
3. **Windows button.** Keep "Download for Windows" in the hero on all screens, but make it the secondary style inside that phone media query rather than removing it.
4. **Top spacing.** In the same phone rule, set `.dl-hero` margin-top to 0 and cut its 96px top padding.
5. **Landing hero.** Add a "Create free account" button next to "Start on the Download page" when signed out. This helps on every device. Then re-run check-landing.js and the mocks.

Owner: Finch. Effort: about 2-3 hours including the checks. The "email me the PC link" form is a separate, larger change: it needs an email-send rate limit and a decision on abuse handling. | Gate the phone block on input capability plus width, not width alone. Use `@media (max-width:700px) and (hover:none) and (pointer:coarse)`, the same capability test the repo already uses for the upload dialog's tap wording.

1. In that query on /Download, show a block at the top of the hero: "On your phone? Create your free account now, then open folderbird.com/download on your PC." Give it a solid "Create free account" button pointing to /Account/Register.
2. Reorder the buttons with CSS `order` and keep all of them visible. Register goes first, then Google Play, then Windows and Linux. Do not hide the Windows button: some visitors are reading on the phone and will download on the PC.
3. Make Play full size only for Android visitors. CSS cannot tell Android from iOS, so either label it "Android: Get it on Google Play" or add a small `navigator.userAgent` check that only raises the Play badge's prominence. Never show iPhone users a working-looking store button while the App Store listing is still "Soon".
4. Inside the same query, cut `.dl-hero` margin-top from 56px to 0, or to a small value.
5. On the landing, add a "Create free account" button to `.hero-cta`, shown only under that query. Today the only Register link on a phone is behind the burger.

Leave the cookie banner alone in this change; it is a separate consent decision. To verify, run tools/screenshot-mocks check-landing.js and render the page at 412px with touch emulation, the way shot-caps.js already does.

## 6. [landing] /Download is a dead end after the click: downloading the installer shows no 'next: create your account' step
- Severity: high · kept 2/2 · owner: Finch · live site: yes · effort: About 1 hour; staging, then swap
- Evidence: Download/Index.cshtml:159 and :223 are plain `<a href="/download/windows/setup">` links. The page's only script (:295-365) handles the Installer/Portable toggle; nothing reacts to a download click. The one account link is step 2 text at :185, 'No account yet? <a href="/Account/Register">Create one free</a>', below the hero. :202 'A Folderbird account (free to create)' is not a link.
- Impact: The 3 Google visitors who downloaded the installer were never shown 'create your free account' at the one moment they were clearly committed, and the app itself cannot send them there (Swift finding).
- Fix: For signed-out visitors, put a solid 'Create your free account' button in the /Download hero next to the Windows button (check User.Identity in the view). Also, on click of any Windows download button, reveal a panel without blocking the download: 'Your download has started. Next: create your free account (1 minute), then sign in to the app with it' -> /Account/Register. Skip the panel for signed-in users.
- Reviewer correction: Owner: Finch. Live-site change (staging, then swap), about 1 to 1.5 hours.

1. In the view, check User.Identity?.IsAuthenticated. For signed-out visitors, add a "Create your free account" button to the hero row next to the Windows and Linux buttons, linking to /Account/Register.
2. Add a click listener to #fbHeroWin and to every .dl-plat-btn whose href starts with /download/windows. It must not call preventDefault, so the download (Content-Disposition attachment) keeps working, and it should run only for signed-out visitors. It reveals an inline panel near the hero: "Your download has started. Next: create your free account (1 minute), then sign in to the app with it", with a button to /Account/Register.
   - Bind the listener to the elements, not to a fixed href: the toggle script rewrites the hero href between the installer and the ZIP.
   - Do not block the download, and do not use a modal that opens a new tab.
   - Signed-in visitors can see a short "Now sign in to the app with <their email>" line instead, or nothing.
3. Change the closing line at :291 from "New here? See how Folderbird works" (/alternatehome) to "New here? Create a free account" (/Account/Register).
4. Optional: make "A Folderbird account (free to create)" at :202 a link to /Account/Register.

Check in both themes and at 412px. The panel must use the theme tokens, not an inline background colour (the 2026-08-26 dark-mode trap). The hero button row stacks at 560px or narrower, so a third button there needs a test that it stays on one line. Separately, the app-side gap (no Register link on LoginForm) belongs to Swift and needs a signed Windows release. | The fix direction is right; refine it as follows (owner Finch; changes the LIVE site, through staging and then a swap; about 1 to 1.5 hours).

1. In Views/Download/Index.cshtml, when `User.Identity?.IsAuthenticated != true`, add a solid "Create your free account" button (/Account/Register) to the hero `.dl-btnrow`, beside or under the Windows button.

2. Add a signed-out-only "Next: create your free account" panel that appears after a click on any Windows download link: #fbHeroWin, the two .dl-plat-btn links and the :247 fallback ZIP link. Use one delegated click listener on `a[href^="/download/windows"]`.
   - Never call `preventDefault`. The attachment must still download.
   - The listener must read the href at click time, because the toggle script rewrites the hero href.
   - Put the listener inside the existing `init()` that waits for DOMContentLoaded. `_Layout` renders the scripts section above the page body, so it would otherwise find no elements.
   - Render the panel markup server-side with the `hidden` attribute, and only inside the signed-out branch. The script then just un-hides it, and signed-in users never get it.

3. Panel copy: "Your download has started. Next: create your free account, then sign in to the app with the same email and password." Do not promise "1 minute". Website sign-in needs the confirmation email; the app sign-in does not (`RequireConfirmedEmail=false` on `api/auth`).

4. Change the :291 footer note so signed-out visitors get "New here? Create a free account" instead of only "See how Folderbird works".

Pair it with Swift's app-side fix: a "No account? Create one at folderbird.com" link on LoginForm. Without it, someone who downloads now and installs later still hits a dead end.

## 7. [landing] Paid-plan buttons send new visitors to Sign in, and the subscription intent is lost if they register
- Severity: medium · kept 2/2 · owner: Finch · live site: yes · effort: 1-2 hours for the button and Register returnUrl; more if the returnUrl must survive the email-confirm round trip
- Evidence: Views/Home/Pricing.cshtml:214 `if (!P.auth) { window.location = '/Account/Login?returnUrl=%2FPricing'; return; }`. Views/Account/Login.cshtml:65-66 'Don't have an account? @Html.ActionLink("Register", "Register", "Account", new { }, ...)' does not carry returnUrl. Controllers/AccountController.cs:147 `public IActionResult Register()` takes no returnUrl. The free plan's button is the outlined `btn-buy ghost` (Pricing.cshtml:75), while Falcon is the solid 'Most popular' (:79-93).
- Impact: A visitor ready to pay lands on a sign-in form, and if they create an account they never get back to checkout. Subscriptions are lost even when intent exists. The free-plan button is also visually the weakest on the page.
- Fix: For signed-out visitors, send 'Choose Falcon/Eagle' to /Account/Register?returnUrl=/Pricing?plan=falcon. Accept a local-only returnUrl in Register, keep it through CheckInbox/ConfirmEmail, and land on /Pricing after confirmation. Label Sparrow's button 'Start free' and make it solid when signed out.
- Reviewer correction: Finch; changes the live site; about 1.5-3 hours.
(a) Pricing.cshtml:214, when signed out: go to `/Account/Register?returnUrl=%2FPricing%3Fplan%3D<tier>` (the plan and the monthly/yearly choice in the query). On Register, show "Already have an account? Sign in" that carries the same returnUrl.
(b) Login.cshtml:66: pass `new { returnUrl = ViewBag.ReturnUrl }` to the Register link.
(c) `Register(string returnUrl = null)`: keep it only if `Url.IsLocalUrl(returnUrl)` is true, and carry it as a hidden field into RegisterAsync. Do not put it in the confirmation email link. Store it in a short-lived HttpOnly cookie (Path=/Account, 24 h) set next to `fb.reg`, or inside the `fb.reg` payload.
(d) ConfirmEmail, state `signedin`: if that cookie holds a valid local URL, the main button becomes "Continue to Falcon checkout" and goes to /Pricing?plan=falcon. Keep "Go to my devices" as the second option. For the `confirmed` state (another browser, not signed in), point the Sign in button at `/Account/Login?returnUrl=<same>`.
(e) Pricing: when a known `plan` is in the query and the visitor is signed in, highlight that tier and show a "Continue to checkout" banner or button. Do NOT call Paddle.Checkout.open on page load; let the person click.
Check with `Url.IsLocalUrl` at every hop to avoid an open redirect, and never echo the value into a script context without encoding it. The restyle of the Sparrow button is optional polish and does not belong in this fix. | 1. In Pricing.cshtml:214, send signed-out visitors to `/Account/Register?returnUrl=%2FPricing%3Fplan%3D<tier>`. Pass the same returnUrl on Login.cshtml:66's Register link and Register.cshtml:63's Sign-in link, so either path keeps the intent.
2. Give `Register(string returnUrl)` the parameter, keep it in a hidden field, and only accept it if `Url.IsLocalUrl` passes. In RegisterAsync, store it in a short-lived HttpOnly cookie (for example `fb.intent`, Path=/Account, 24 h, data-protected like fb.reg). Do not put it in the confirmation email link.
3. In ConfirmEmail's "signedin" state, if the intent cookie is valid, point the primary button at that local URL ("Continue to the Falcon plan"), keep "Go to my devices" as the secondary, then delete the cookie. Append the same returnUrl to the "confirmed" state's Sign-in link, so a confirmation opened on another device still returns to /Pricing after sign-in.
4. On /Pricing, when `?plan=` is present and the visitor is signed in, highlight and scroll to that tier instead of auto-opening Paddle. A brand-new account has no PC yet, and P.managed must still win.
5. Optionally relabel Sparrow's button "Start free". Keep it outlined so "Most popular" stays the visual anchor.

Owner: Finch. Changes the live site after a swap. Effort: about 2-3 hours, including a staging click-test of both the same-browser and cross-device confirmation paths.

## 8. [landing] Headline does not say plainly what the product does, and the eyebrow contradicts it
- Severity: medium · kept 2/2 · owner: Finch · live site: yes · effort: About 30 minutes
- Evidence: AlternateHome.cshtml:827 eyebrow 'Your personal cloud' (bi-cloud-check icon) immediately above :828 H1 'Your PC's files with you anywhere & AI enabled, without moving them to the cloud.' The lead (:829-832, 56 words) packs browse/search/download/upload/manage, 'private cloud', 'Nothing is synced' and the AI connector into one block. The meta description (:27) is clearer than the visible hero.
- Impact: An ad visitor has seconds. 'Cloud' and 'not the cloud' within two lines, plus 'AI enabled', blur the core promise (open your home PC's files from your phone or any browser). There is no one-sentence answer to 'what is this, and is it free?'
- Fix: Suggested: eyebrow 'Remote access to your PC's files'. H1 'Open your PC's files from your phone or any browser.' Sub 'Free for 2 PCs. Nothing is uploaded to a cloud.' Move the AI line into the proof strip or the AI section. Keep the copy wording consistent with the 'never synced, never stored' rule in CLAUDE.md.
- Reviewer correction: Owner: Finch. Edit only Views/Home/AlternateHome.cshtml lines 827-832.

1. Eyebrow: "Remote access to your PC's files". Keep or swap the bi-cloud-check icon (bi-pc-display fits).
2. H1: "Open your PC's files from your phone or any browser." The h1-after span becomes "Free for 2 PCs. Your files stay on your PC, never synced to a cloud."
   - Do NOT write "nothing is uploaded to a cloud", "never copied" or "never stored". Transfers pass through the server bucket, and Blob holds them for up to 2 h.
   - "Free for 2 PCs" is accurate: Sparrow is $0 with DeviceLimit defaulting to 2.
3. Shorten the lead to one sentence, for example: "Install one small app on your Windows PC, sign in, and browse, search, download and upload its files from anywhere; a transfer only passes through."
4. Move the AI-agents line into the AI section. The proof strip already has "REST + MCP, permission-scoped".
5. Consider moving the lead above the screenshot on ≤980px (lines 482-483 set the order), or rely on the new H1/sub, which then carries the message on phones by itself.
6. Run `python3 render_landing.py && node check-landing.js` in tools/screenshot-mocks to confirm the hero still fits at 412px and 1200px.

Deployment: the change touches the live site, but it only reaches production after the merge to main (which deploys staging) and a swap. Effort is about 30-45 minutes including the landing check. | Keep the new eyebrow and H1, but replace the suggested subline. "Nothing is uploaded to a cloud" is false. A browser upload sits in the server's bucket until the PC fetches it. Phone, REST and MCP transfers are staged in Azure Blob for up to 2 hours. Upload is also an advertised feature. The rule the finding cites ("never synced, never stored") is out of date. Decision H (commit 61135f9, 8 Nov) replaced it. tests/storage_wording_tests.js rejects "never stored", "never copied" and the exact phrase "never synced, never stored". Use: eyebrow "Remote access to your PC's files", and change the bi-cloud-check icon to a PC or plug icon. H1 "Open your PC's files from your phone or any browser." Keep the existing `<span class="h1-after">` subline (styled at line 171) with "Free for 2 computers. Nothing is synced, and a transfer only passes through." "Free for 2" matches Pricing.cshtml:67-69. Cut the lead to one sentence (browse, search, download, upload from any browser; install one small app). Move the AI clause into the proof strip, which already has "REST + MCP, permission-scoped", or leave it to the AI section. Keep "a transfer only passes through" on the page; the og:description at line 34 also carries it, and the storage test checks for it. Before pushing, run node tests/storage_wording_tests.js, node tests/pre_ads_copy_tests.js and tools/screenshot-mocks/check-landing.js. Owner: Finch. Wren should then check whether the Google Ads headlines say "personal cloud" and match them to the new H1; that is unknown because the ad copy is not in the repo. Push to main and it goes to staging only. Live production needs a swap, and that needs Majid's go. Effort: about 30-45 minutes including tests.

## 9. [landing] Landing ships heavy render-blocking CSS for a few icons, plus eager below-fold images
- Severity: low · kept 2/2 · owner: Finch · live site: yes · effort: 1-2 hours
- Evidence: <head> render-blocking stylesheets: AlternateHome.cshtml:75 bootstrap-icons.min.css (86,175 B), :77 /Content/dist/file-icon-vectors.css (174,103 B, 2,201 'fiv-' rules; the page uses 7 classes, all in the hero mock: fiv-icon-txt/pdf/png/blank/folder-classic). bootstrap-icons.woff2 is 130,396 B. The HTML itself is about 130 KB uncompressed. devices.jpg (114 KB) at :1061 and caps/upload(-m).jpg at :1107 have no loading="lazy", although both are thousands of px below the fold. Program.cs has no UseResponseCompression; whether App Service compresses these responses is unknown (check Content-Encoding on a live response).
- Impact: Phone visitors on mobile data in the Facebook in-app browser wait for about 260 KB of CSS before first paint, and this compounds the first-screen problem. Probably secondary to the CTA findings.
- Fix: Replace the 5 fiv icons in the hero mock with bootstrap-icons or inline SVG and drop file-icon-vectors.css from the landing. Add loading="lazy" to devices.jpg and the first caps picture. Check gzip/brotli on prod before adding compression middleware.
- Reviewer correction: Owner: Finch. This changes the live landing page once swapped. About 1 hour.

0. First, have someone with a working browser or device (not this session, whose proxy blocks folderbird.com) fetch /Content/dist/file-icon-vectors.css from production with `Accept-Encoding: gzip, br` and read Content-Encoding.
   - If there is none, adding `AddResponseCompression` + `UseResponseCompression` (Brotli/Gzip for text/css, js, html, svg; EnableForHttps) before `UseStaticFiles` is the single biggest lever. It cuts the two sheets from 260 KB to about 29 KB on every page.
   - This touches every response, so verify on staging first: the device long-poll endpoints and the DownloadFileNow stream must not be buffered. Exclude `application/octet-stream`, or keep compression to text MIME types only.

1. Do NOT replace the fiv icons with bootstrap-icons. The comment at `AlternateHome.cshtml:881-883` says the hero deliberately uses "the same file-icon-vectors classic folder the real listing renders".
   - Instead, remove the `<link>` at line 77 and paste the handful of rules the page needs into its own `<style>` block: `.fiv-hct`, `.fiv-ext`, `.fiv-size-md`, `.fiv-hct.fiv-icon-{txt,pdf,png,blank}` and `.fiv-ext.fiv-icon-folder-classic`.
   - Rewrite their relative `url("icons/...")` to absolute `/Content/dist/icons/...`, or the icons will 404.
   - Leave `Views/Device/Index.cshtml:12` alone; the real browse page needs the full sheet.

2. Add `loading="lazy"` to `devices.jpg` (line 1061) and to the light `upload.jpg` `<img>` (line 1107). Also add width/height (or aspect-ratio) to them so lazy-loading does not add layout shift.

3. Afterwards, run `tools/screenshot-mocks/check-landing.js` and `check-secmenu.js` (the section-jump checks), and look at the hero at 412px and 1440px in both themes. | 1. **Check compression first.** Look at `Content-Encoding` on `/Content/dist/file-icon-vectors.css` and on `/` in production.
   - If nothing is compressed, add `AddResponseCompression` (Brotli and Gzip, `EnableForHttps=true`) before `UseStaticFiles`. Limit `MimeTypes` to text/css, application/javascript and image/svg+xml, and leave out text/html, because the HTML carries antiforgery tokens (the BREACH attack). Compressing CSS cuts it about 9x for every page, not only the landing.

2. **Drop file-icon-vectors.css from AlternateHome but keep the hero looking the same.** The comment at :883-885 says the mock deliberately uses the same classic folder icon the real browse page renders. So copy the roughly ten rules the hero needs into the page's own `<style>` block instead of swapping icons:
   - `.fiv-ext`, `.fiv-ext:before`, `.fiv-ext.fiv-icon-folder-classic` (css lines 8829-8831)
   - `.fiv-hct`, `.fiv-hct:before`, and the blank, pdf, png and txt rules (around lines 4438-4447, 4605, 5369, 5413, 5693)
   - `.fiv-size-md`
   - Rewrite the `url("icons/...")` paths as absolute `/Content/dist/icons/...` paths. Then remove the `<link>` at :77.

3. **Lazy-load the two images.** Add `loading="lazy"` to devices.jpg (:1061) and to the upload `<img>` at :1107. Also give devices.jpg `width`/`height` (or an aspect-ratio), so the section-menu jump does not have to correct a late layout shift.

4. **Check before pushing.** Run `python3 render_landing.py` plus `check-landing.js`, and look at the hero in both themes at 412 px and at desktop width.

**Owner, effort, and when it reaches production:** Finch, about 1-2 hours. A push to main reaches staging only; production changes only after a swap.

## 10. [landing] Google Ads gets no signal short of a confirmed email: no event for installer download or sign-up start
- Severity: low · kept 2/2 · owner: Finch (code), then Wren (Ads console) · live site: yes · effort: About 1 hour of code + 15 minutes in the console
- Evidence: The only Ads conversion in the views is Views/Account/ConfirmEmail.cshtml:99 `gtag('event', 'conversion', ...)`. grep finds no gtag event on /Download clicks, /Account/Register views, or submits. The tag itself only loads after Accept (_GoogleTag.cshtml basic consent).
- Impact: With 0 confirmed sign-ups, Smart Bidding has nothing to optimise toward, so spend (SAR 114, 0 conversions) cannot shift toward people who download or start signing up. This costs ad efficiency rather than sign-ups directly.
- Fix: Fire consent-gated gtag events on Windows-download click and Register submit. Then have Wren add them in the Ads console as secondary conversions (observation only, so they do not replace the confirm-email primary).
- Reviewer correction: Step 0 (Majid or Finch, read-only, 2 min): check whether App Service `GoogleAds__ConfirmSignupLabel` is set on the production slot. If it is unset, the confirm-email conversion can never fire, and setting it (Wren creates the action and supplies the label; the setting needs no redeploy) is the first fix.

Step 1 (Finch, about 1 hour, changes the LIVE site after a swap):
- In AccountController.Register's success branch (:229-250), set a one-shot TempData flag, for example `TempData["fbSignupCreated"]=true`, before the redirect.
- In CheckInbox.cshtml, emit `gtag('event','sign_up_created', {...})`, or an AW conversion with its own config label, only when that flag is present. Copy ConfirmEmail.cshtml's pattern: `typeof gtag` guard plus `fbAfterGtag` queue, `Json.Serialize`, fail-safe when the label is unset, and the user id as `transaction_id`. Do not fire on the client-side form submit.
- On /Download, add a click listener on `#fbHeroWin` and `.dl-plat-btn` that sends `gtag('event','windows_download', {flavor})` when `typeof gtag==='function'`. Do not delay the navigation; gtag uses beacon transport.
- Both events stay consent-gated as they are today.

Step 2 (Wren, 15 minutes, console only): create the two conversion actions.
- Be explicit about the trade-off. Secondary or observation means visibility only; it does not change bidding.
- If the goal is to give a Smart Bidding campaign something to learn from while confirmed sign-ups are near zero, make "sign-up created" PRIMARY temporarily, alongside confirm-email. Keep the download event secondary: it would optimise toward people who download and never register, which is the current failure pattern.
- Revisit once confirm-email conversions accumulate. | Keep the finding but change where the sign-up event fires.

1. Don't fire it on Register submit. That submit also happens when validation, the password rule or the captcha fails, and it navigates away while the hit is still in flight. Fire an 'account_created' event on CheckInbox instead, and only after a real registration. Set a one-shot TempData flag next to `TempData[PendingEmailKey] = user.Email;` in RegisterAsync (AccountController.cs:249). CheckInbox reads the flag and emits the event. CheckInbox alone is not enough, because the resend and expired-link redirects (AccountController.cs:350, 375, 423, 433) also land there. Use the same `typeof gtag === 'function'` / `window.fbAfterGtag` pattern as ConfirmEmail, so the event fires only with consent.
2. For the installer, add a consent-gated click handler on links whose path is /download/windows/setup or /download/windows. Send a 'windows_download' event, with `transport_type: 'beacon'` (or no navigation wait, since the link is a file response and the page stays put).
3. Wren then adds both events in Ads as SECONDARY conversions, so they are observed but not optimised on. Wren also confirms that the primary label `GoogleAds__ConfirmSignupLabel` is actually set in App Service.

All of this is consent-gated, so it undercounts the same way GA4 does. Owner: Finch for code (live site), Wren for the console. Effort: about 1 hour of code and 15 minutes in the console.

## 11. [landing] Hero mock shows Majid's real laptop name and a 1.2-second latency labelled 'Good'
- Severity: low · kept 2/2 · owner: Finch · live site: yes · effort: 5 minutes
- Evidence: AlternateHome.cshtml:851 `<b>LAPTOP-MOGV95CM</b>` (the owner's real laptop, device 39 per CLAUDE.md). :852 `Good · 1181 ms`. On phones this mock fills most of the first screen.
- Impact: Minor. 1,181 ms reads as slow to a technical visitor, and a real machine name on a public page goes against the repo's own 'no real machine names on public pages' rule.
- Fix: Use a fictional name (for example HOME-PC) and a realistic figure such as 'Good · 140 ms'.
- Reviewer correction: In Views/Home/AlternateHome.cshtml:851, replace `LAPTOP-MOGV95CM` with `HOME-DESKTOP`. That is the fictional name every other landing screenshot already uses (tools/screenshot-mocks/build.py, build_modals.py), so the hero and the screenshots further down agree.

On :852, optionally lower the figure to something like `Good · 140 ms`. Keep it under LightHouse.CONN_SLOW_MS (1500) so the label stays true to the app's own ladder.

Afterwards, run `python3 tools/screenshot-mocks/render_landing.py && node tools/screenshot-mocks/check-landing.js`.

The owner is Finch and the effort is about 5 minutes. It touches production only after the push to main (which deploys to staging) and a swap. | Finch. In Views/Home/AlternateHome.cshtml:
- Line 851: replace LAPTOP-MOGV95CM with a made-up name that fits the "Alex" folder, such as HOME-PC (the Play listing already uses HOME-DESKTOP).
- Line 852: use a realistic figure such as 'Good · 140 ms'. Any value under 1500 is consistent with the real scale in LightHouse.cs:1438.

Then grep the screenshot builders and the landing images under tools/screenshot-mocks for the real hostname. The source grep found nothing, but whether the name appears as pixels inside the images is unknown. A push to main reaches staging only; the live site changes only after the usual swap.

Effort: about 5 minutes, plus one look at a phone-width render.

## 12. [account] After confirming, the next step offered is two-factor, not installing the app; the empty devices page hides the download
- Severity: high · kept 2/2 · owner: Finch · live site: yes · effort: 2-4 hours
- Evidence: Views/Account/ConfirmEmail.cshtml:63-78: the only next step on "You're in" is "🔐 One more thing worth doing … Add two-factor authentication … needs an authenticator app" with Set it up / Not now. Views/Device/DeviceList.cshtml:440-445: a zero-device account sees only "<p>No devices yet.</p>" and a small line "To add more computers, <a href=\"/Download\">download the app</a>". DeviceList.cshtml:198 + 496-499: "Add a device" calls window.prompt('Add a new PC:\n1) Install the Folderbird app on that PC…', code). It has no link or button to the installer. Controllers/DeviceController.cs:62-126 (Index) does nothing special for zero devices. grep finds no "email me the download link" feature anywhere in Views.
- Impact: A confirmed account with no PC connected gets no value, and plans are sold per device, so it can never upgrade. The one moment the person is signed in and paying attention is spent on an authenticator-app chore. A phone visitor (most ad traffic, 3 of 5 Meta visits from in-app browsers) is pointed at a Windows installer they cannot use on the phone, and nothing tells them how to get it onto the PC.
- Fix: Replace the 2FA box on "You're in" with an install card. Desktop: a big "Download for Windows" button (/download/windows/setup) and "then sign in with <email>". Phone: "Open folderbird.com/download on your PC" plus an "Email me the download link" button. That button sends only to the account's own address through the existing IFbEmailSender, with its own rate limit like ResendConfirmation. Use the same card as the zero-device state on /Device, above the search box. Show the 2FA nudge only after the first device is connected.
- Reviewer correction: Owner: Finch. This is web code only, but it reaches the LIVE site once it is pushed to main (staging) and swapped.

1. ConfirmEmail.cshtml, in both the "signedin" and "confirmed" states: add an install card. Keep "Go to my devices" (or "Sign in") as the button.
   - The card has a primary "Download for Windows" button pointing to /download/windows/setup, a small "Linux (beta)" link to /Download, and the line "then sign in to the app with this email and password".
   - For people on a phone, add the line "On your phone? Open folderbird.com/download on your PC". Show it with a CSS (pointer:coarse) / (hover:none) rule, the same method _Layout already uses for the upload wording, not by reading the browser's User-Agent. In-app browsers lie in the UA.
   - Remove the 2FA box from this page.

2. DeviceList.cshtml, when an account has zero devices: replace "No devices yet." and the "To add more computers" line with the same card. Place it above the search box and hide the search box while there are no devices. Keep the "add more" wording only for accounts that already have devices. Also add a download link to the fbAddDevice prompt text.

3. Bring the 2FA nudge back only once the account has at least one device. It can go on /Device, using the 2FA state already available through the user manager. If 2FA comes before the first device, the device-code gate in AuthController.cs:944-949 blocks the first sign-in in the app.

4. Optional second step: an "Email me the download link" button.
   - It sends only to the signed-in account's own confirmed address, through the existing email sender.
   - It needs its own rate limit (per account and per caller, as on ResendConfirmation) plus a daily cap.
   - Do not take this on before steps 1 to 3.

Effort: about 1 to 1.5 hours for steps 1 to 3, plus 1 to 2 hours for step 4. Check the card in both themes, using theme tokens and no inline background colour, at 412px and 1200px wide. | The direction is right. Adjust it as follows.
(a) Show the install card in all four ConfirmEmail states (signedin, confirmed, confirmed2fa, setup2fa), not only "signedin". The phone and in-app-browser case usually lands in "confirmed" and today sees only "Sign in".
(b) Leave the Ads conversion <script> block at the bottom of ConfirmEmail.cshtml exactly as it is, and the ViewBag.ConfirmedUserId it reads.
(c) Card content: "Download for Windows" linking to /download/windows/setup (the route exists, DownloadController.cs:102), then "sign in in the app with <email>", plus a small link to /Download for Linux (beta). Choose the phone or desktop wording with the CSS capability query the site already uses, @media (hover:none) and (pointer:coarse), as on the upload dialog. Do not sniff the user agent, and render both versions so nothing breaks if the guess is wrong.
(d) The cheapest way to reach phone users needs no new endpoint: put "Install the app on your PC: https://folderbird.com/Download" in the confirmation email (AccountController.cs:311). It is already in the user's inbox and they can open it on the PC. If you still add a signed-in "Email me the download link" button, it must have [Authorize] and [ValidateAntiForgeryToken], send only to the signed-in user's own confirmed address, carry the existing "email-send" rate-limit policy, and have a per-account daily cap. Without the cap, any signed-in session can trigger repeated sends.
(e) Put the same card on the zero-device branch of DeviceList.cshtml (replace "No devices yet." at line 442), and give the fbAddDevice prompt a real link to /download/windows/setup instead of plain text.
(f) Move the 2FA nudge to after the first device is connected. Do not delete it.
Owner: Finch. It changes the live site after the swap. Effort: about 2-3 hours with (d) as the email-copy change, plus about 1 hour if the new email endpoint is added.

## 13. [account] A confirmation link opened in another browser means signing in again, with nothing pre-filled, and ending on the marketing home page
- Severity: high · kept 2/2 · owner: Finch · live site: yes · effort: 30-60 minutes
- Evidence: Controllers/AccountController.cs:462-473: sign-in at confirmation only happens if the fb.reg cookie is present ("if (!fromRegisteringBrowser) { ViewBag.State = \"confirmed\"; return View(\"ConfirmEmail\"); }"). The cookie is set at :243-247 with Path=/Account and a 1-day life, in the registering browser only. Views/Account/ConfirmEmail.cshtml:59 says "Your account is ready. Sign in to continue." and :81 links Url.Action("Login", "Account") with no returnUrl. Login.cshtml:37 starts with an empty email field. After sign-in, AccountController.cs:1284-1293 RedirectToLocal(null) goes to RedirectToAction("Index", "Home"), and Controllers/HomeController.cs:28 returns View("AlternateHome"), the ad landing page.
- Impact: This is the normal path on phones. Someone who registers inside the Facebook/Instagram in-app browser always opens the mail link in another browser, and so does anyone who registers on a desktop and reads mail on a phone. They must remember and retype the password they just made, then land on the page they came in through, which feels like going round in circles. Every website sign-in without a returnUrl, including the navbar's Sign in, also lands on '/' instead of /Device.
- Fix: (1) In ConfirmEmail.cshtml, link Sign in with Url.Action("Login", "Account", new { returnUrl = "/Device" }). (2) Make RedirectToLocal's fallback RedirectToAction("Index", "Device"). (3) Pre-fill the email on Login from TempData (never the URL, same as CheckInbox) when coming from a confirmed link. The fb.reg security rule stays as it is.
- Reviewer correction: Owner Finch. Web code only; it reaches the live site after the usual staging deploy and swap. About 30-45 minutes.

(1) ConfirmEmail.cshtml:81 becomes `Url.Action("Login", "Account", new { returnUrl = continueUrl })`. The variable already exists at :30, and this covers the confirmed, confirmed2fa and setup2fa states.

(2) RedirectToLocal (:1292) falls back to `RedirectToAction("Index", "Device")` instead of Home. Every caller is post-sign-in, so this is safe, and it also fixes the navbar and landing Sign in links.

(3) Pre-fill the email:
- In ConfirmEmail, set `TempData["LoginEmail"] = user.Email` only on the non-signed-in branches (the `!fromRegisteringBrowser` and 2FA returns). Do this after the token has validated.
- In the Login GET, use `new LoginViewModel { Email = TempData["LoginEmail"] as string }`.
- Never put the email in the URL.

TempData is cookie-scoped, so a mail scanner's pre-fetch only sets it in the scanner's own jar, which is harmless.

Keep the fb.reg rule unchanged. Do not "fix" the retype-password step by signing in without the cookie; that reopens the register-a-victim's-address takeover documented at :457-461. | 1. **Fallback.** Change RedirectToLocal's fallback (AccountController.cs:1292) to `RedirectToAction("Index", "Device")`. All callers (:121, :754, :762, :1093, :1143, :1182) run after a successful sign-in, so this is safe. It also fixes the navbar and Download-page Sign in links, which pass no returnUrl.
2. **Pre-fill the email.** In ConfirmEmail, set `TempData[PendingEmailKey] = user.Email` before each "Sign in to continue" render. That means the stale-link "confirmed" branch (:416-419), the confirmed2fa/setup2fa branch (:455) and the not-from-registering-browser branch (:469-473). In Login GET, read it with `new LoginViewModel { Email = TempData[PendingEmailKey] as string }`. Never put the address in the URL.
   - TempData here is the default cookie provider, so it works inside the second browser.
   - It shows the address only to someone holding a valid token link for that address. That is acceptable.
3. **Optional.** Add `new { returnUrl = "/Device" }` to the ConfirmEmail Sign in link (:81) and to CheckInbox.cshtml:54. Step 1 makes this redundant for plain sign-in, but it is harmless and it carries through the 2FA routes (SetupTotp and VerifyTotp keep ReturnUrl).
4. **Keep the fb.reg check exactly as it is.** Do not widen it to sign in from other browsers.

## 14. [account] The registering tab stays on "Check your inbox" after the link is clicked on another device
- Severity: high · kept 2/2 · owner: Finch · live site: yes · effort: 2-3 hours
- Evidence: Views/Account/CheckInbox.cshtml (whole file, lines 1-58) has no script and no polling. No controller action reports whether an account is confirmed: AccountController.cs only has CheckInbox / ResendConfirmation / ConfirmEmailAsync (:327-485).
- Impact: A desktop visitor who confirms on their phone goes back to the PC and finds the same "Check your inbox" page. Nothing says it worked. They have to find Sign in by themselves, and per the finding above they then land on '/'. Each extra unguided step loses people.
- Fix: Have CheckInbox poll a small GET /Account/ConfirmStatus every 4 s for up to about 30 min. It uses the fb.reg cookie (which already proves this browser registered) and returns only true/false. When it turns true, sign this browser in and go to the install card. This gives no new access: the registering browser's owner set the password and could sign in anyway. Add a rate limit and return the same answer for an unknown or expired cookie.
- Reviewer correction: Owner: Finch. This changes the LIVE site after the swap.

Step 1, about 15 minutes, and most of the value. Give both Sign in links a returnUrl to /Device: CheckInbox.cshtml:54 (Html.ActionLink with new { returnUrl = Url.Action("Index","Device") }) and ConfirmEmail.cshtml:81. Make the CheckInbox one a visible secondary button instead of muted small text. This fixes the "lands on the marketing page" problem for every route, including the case where someone registers inside the Facebook app and confirms in Chrome, which polling cannot help.

Step 2, about 1-2 hours, optional:
- Add GET /Account/ConfirmStatus [AllowAnonymous]. Without a valid fb.reg cookie (missing, expired, or one that fails to unprotect) it returns {confirmed:false}. With a valid cookie it returns {confirmed: IsEmailConfirmedAsync(user)}, with Cache-Control no-store and its own small per-caller limiter (for example 60 per 15 minutes). Do not reuse the resend-confirm bucket.
- Do the actual sign-in NOT in that GET, but in a separate antiforgery POST /Account/ContinueAfterConfirm. It must mirror ConfirmEmailAsync exactly:
  - fb.reg unprotects to the user id;
  - the email is confirmed;
  - two-factor is NOT enabled (otherwise redirect to Login, as states confirmed2fa / setup2fa do);
  - then SignInAsync, delete fb.reg with Path=/Account, write the audit row, and redirect to /Device.
- In CheckInbox, check status on visibilitychange or focus (the person coming back to the PC tab) plus a slow fallback poll every 15-20 s, stopping after about 30 min or when the tab is hidden. Avoid a fixed 4-s poll.
- On {confirmed:true}, replace the card with "Email confirmed - Continue" that submits the POST. Do not sign in silently.

Do not fire the Ads conversion on this path; it already fired on ConfirmEmail. | Interim fix, Finch, a few minutes, live once swapped: change the line-54 link into a visible "I've confirmed, sign in" button. Give it returnUrl=/Device, and put the address in the sign-in form's email field so the person does not retype it.

Full fix, Finch, about 3-4 hours including tests, live once swapped:

(1) At registration, protect "userId|securityStamp" in fb.reg instead of the bare id. Use _userManager.GetSecurityStampAsync. ConfirmEmailAsync does not rotate the stamp, but a password reset or a 2FA change does. Update ConfirmEmailAsync's check at :465 to compare the id part. Old cookies then simply fail to match, which is safe.

(2) Add a GET /Account/ConfirmStatus. It must stay under /Account, because the cookie has Path=/Account. It reads fb.reg and returns only {confirmed:true|false}. It returns false for a missing, expired or foreign cookie, or when the stamp no longer matches. Give it its own rate-limit policy, for example 120 per 15 min per caller, and send `Cache-Control: no-store`.

(3) In CheckInbox, check the status when the tab regains focus (visibilitychange/focus, which is exactly the case of coming back to the PC). While the tab is visible, also check every 10-15 s, and stop after 30 minutes. When the answer is true, swap the card to "Email confirmed - Continue". Continue is a top-level antiforgery POST to /Account/ContinueAfterConfirm. The page already renders a token in the resend form.

(4) That POST re-checks everything ConfirmEmail checks: fb.reg unprotects to this user, the stamp matches, the email is confirmed, the account is not locked out (IsLockedOutAsync), and GetTwoFactorEnabledAsync is false. If 2FA is on, send the person to Login instead. Then SignInAsync, delete fb.reg, write the same "login" audit row, and redirect to /Device, where ConfirmEmail's "Go to my devices" goes. The finding's "install card" target was not checked in the source and is unknown.

Push to main deploys to staging; the live site changes only when staging is swapped to production.

## 15. [account] The Windows app has no "Create account" link: installing first leads to "Incorrect email or password"
- Severity: high · kept 2/2 · owner: Swift (app), Majid (code signing), Finch (web stop-gap) · live site: yes · effort: App 1-2 hours plus a signing/release session; web stop-gap 30 minutes
- Evidence: folderbird-agent FileRouteClient/LoginForm.Designer.cs:236-246: the only controls are lblFooter, progressBar1, btnLogin, lblMessage, chkShowPassword, chkRemember, txtPassword, lblPassword, txtEmail, lblEmail, panelHeader. There is no LinkLabel and no "Create account" or "Forgot password". LoginForm.cs:143-149 shows "Incorrect email or password. Please try again." for LoginFailed, and the server returns that for an unknown email (folderbird-web Controllers/AuthController.cs:977-980). tools/windows-installer/Folderbird.iss:136: the installer's finish step only starts the app, it does not open a browser to Register. Only /Download step 2 (Views/Download/Index.cshtml:185) says "No account yet? Create one free".
- Impact: Overnight 3 Google-ad visitors downloaded the installer and none signed up. After installing, the first screen they see asks for an account they do not have. A wrong-password message is a dead end for someone who never registered.
- Fix: Swift: add two links to LoginForm. "New to Folderbird? Create a free account" opens https://folderbird.com/Account/Register?src=app (Process.Start of a fixed URL). "Forgot password?" opens /Account/ForgotPassword. Change the LoginFailed text to "Incorrect email or password. No account yet? Create one free at folderbird.com." This needs a signed Windows release (SSL.com password plus OTPs) and the fleet arming steps, so Majid is needed for signing. Web stop-gap (Finch, live, about 30 min): after the installer button on /Download is clicked, show "While it downloads: create your free account" with a Register button.
- Reviewer correction: Keep the plan, with these refinements.

1. App (Swift): add two LinkLabels under btnLogin.
   - "New to Folderbird? Create a free account" opens https://folderbird.com/Account/Register.
   - "Forgot password?" opens /Account/ForgotPassword. Both routes exist.
   - Open them with Process.Start of a fixed, hard-coded URL. With a test profile, build the URL from the profile's base URL (FOLDERBIRD_BASEURL) rather than hard-coding production.
   - Grow ClientSize (currently 404x404). The last control already ends at y≈394, so the links need room.
   - Change the LoginFailed copy to mention creating an account.
   - A `?src=app` query string is harmless to Register (its GET takes no parameters) but does nothing unless someone adds tracking.

2. Release: new visitors get this from the installer and zip on /Download, so the release must be published with publish-release.ps1. That needs Majid's SSL.com password and three OTPs. Moving WinBlob also means moving the seven DownloadController constants together with the AgentUpdate__* settings, because they are coupled. So the "fleet arming steps" in the finding are indeed required.

3. A web change that helps today without a signed build (Finch, live): put the account step before or beside the download.
   - On /Download, next to the Windows installer button, add a prominent line: "You'll sign in to the app with a Folderbird account — create one free first", with a Register button.
   - Optionally show it again after the click.
   - This is about 30 minutes and changes the live site after a swap.

4. Optional, no app change: the installer's [Run] could get a second unchecked-by-default postinstall entry that opens {#AppUrl}/Account/Register. This still needs a re-signed installer, so it only makes sense bundled with the app release. | The diagnosis stands. Three adjustments to the fix:

1. **App (Swift).** The two links and the message change are right:
   - "New to Folderbird? Create a free account" opens https://folderbird.com/Account/Register.
   - "Forgot password?" opens https://folderbird.com/Account/ForgotPassword.
   - Use `Process.Start` on a fixed literal URL, wrapped in try/catch. On .NET Framework 4.8 this goes through ShellExecute by default.
   - LoginFailed text: "Incorrect email or password. No account yet? Create one free at folderbird.com."
   - Do NOT have the server return a separate "no such user" answer. That would let anyone check which emails have accounts. Keep the server as it is and fix the copy only.
   - The installer can also offer a second `[Run]` postinstall checkbox: "Create my free Folderbird account (opens your browser)", using `Filename: "https://folderbird.com/Account/Register"; Flags: shellexec postinstall skipifsilent nowait unchecked`. It ships in the same signed release.
   - **Correction to the release step:** arming the fleet update is NOT needed for this. Everyone already installed has an account. Only the new download artifacts matter: run `publish-release.ps1` (Majid: SSL.com password and OTPs), then move the seven `DownloadController` constants. Arming is optional and can wait.

2. **Web stop-gap (Finch, live site, about 30-45 min).** This is the cheaper win and ships without a signed release. Put the sign-up prompt on the Download page itself:
   - Under the hero buttons: "Step 1: create your free account" linking to /Account/Register. Or show the same prompt as a panel once the download button is clicked.
   - Change line 291 from "New here? See how Folderbird works" to "New here? Create a free account".
   - Make this a server-rendered link, so it does not depend on the scripts section, which renders above the page body on this layout.

3. **Owners and effort.** Web: Finch, live site, about 30-45 min. App and installer: Swift, about 1-2 h, plus Majid for one signing session.

## 16. [account] A new visitor who clicks a paid plan is sent to Sign-in, and after registering the plan choice is lost
- Severity: high · kept 2/2 · owner: Finch · live site: yes · effort: 2-3 hours
- Evidence: Views/Home/Pricing.cshtml:214: if (!P.auth) { window.location = '/Account/Login?returnUrl=%2FPricing'; return; }. Views/Account/Login.cshtml:66: the Register link is Html.ActionLink("Register", "Register", "Account", new { }, …), which drops the returnUrl. AccountController.cs:147: Register() takes no returnUrl. ConfirmEmail.cshtml:30: continueUrl = Url.Action("Index", "Device"). The chosen tier/period (Pricing.cshtml fbSubscribe(tier), period) is never carried anywhere.
- Impact: The highest-intent visitor (wants to pay) is shown a "Sign in to Folderbird" form they cannot use and must spot the small Register link. After the full sign-up they end up on /Device, not back at checkout, and would have to find Pricing and pick the plan again. Paid conversions leak at exactly this hand-off.
- Fix: Send anonymous visitors to /Account/Register?returnUrl=/Pricing?plan=<tier>%26period=<m|y>. Accept returnUrl in Register GET/POST and the Login view's Register link, check it with Url.IsLocalUrl, and keep it in TempData or a short cookie through CheckInbox and ConfirmEmail. Use it for the "Go to my devices" button (relabel it "Continue to checkout") and for Login. On /Pricing, read ?plan= and open the Paddle checkout automatically once signed in.
- Reviewer correction: The fix is right in shape, but four parts would misfire as written.

1. Keep Login as the destination for anonymous plan clicks. Some of those visitors already have an account and are only signed out. Instead, make the returnUrl survive in both directions: Login.cshtml:66's Register link and Register.cshtml:63's Sign in link both pass `returnUrl = ViewBag.ReturnUrl`. Also relabel the Login page when a returnUrl is present, for example "Sign in or create an account to subscribe", with Register as a visible button rather than small text. Build the returnUrl with `encodeURIComponent('/Pricing?plan=' + tier + '&period=' + period)` so the inner `&` is not split off.

2. Do not rely only on TempData or a cookie to carry the destination through confirmation. The confirmation mail is often opened on a different device or browser (phone vs desktop), and the existing fb.reg cookie is scoped to Path=/Account. Put the validated returnUrl into the confirmation callback URL that SendConfirmationEmailAsync builds. ConfirmEmailAsync then re-checks it with `Url.IsLocalUrl` and only allows `/Pricing` with known plan values.

3. In ConfirmEmail.cshtml, use that URL in all three places: the "signedin" state's main button (labelled "Continue to checkout" when a plan is present), its "Not now" link, and the Sign in link in the confirmed / confirmed2fa / setup2fa states (as `Login?returnUrl=...`). The EnableAuthenticator returnUrl should get it too.

4. On /Pricing, read ?plan= and ?period= only when `P.auth && !P.managed`. Pre-select the billing toggle and show a clear "Continue to Falcon checkout" button, or open the Paddle overlay once. Never open it for an existing subscriber, because that creates a second subscription.

Owner: Finch. The change reaches production through the normal main → staging → swap route. Effort is about 3-4 hours including a test of the cross-browser confirmation path. | 1. Quick win (about 15 minutes, live after the swap). In Pricing.cshtml:214, send an anonymous visitor to `/Account/Register?returnUrl=` + encodeURIComponent('/Pricing?plan=' + tier + '&period=' + period). In Login.cshtml:66, pass `new { returnUrl = ViewBag.ReturnUrl }` so the Register link keeps it. In Register.cshtml:63, do the same for the Sign-in link.

2. Carry the returnUrl through sign-up (about 2-3 hours with a test).
   - Register GET and POST accept `string returnUrl`. Keep it only if `Url.IsLocalUrl(returnUrl)` and, preferably, only if it starts with `/Pricing`, so it cannot become a general redirect.
   - Do not use TempData; it is gone by the time the mail is clicked. Put the URL in the confirmation link itself: `Url.Action("ConfirmEmail", new { userId, code, returnUrl })` in SendEmailConfirmation and in ResendConfirmation. Re-check it with IsLocalUrl in ConfirmEmailAsync and pass it to the view.
   - In ConfirmEmail.cshtml, use it for continueUrl and for the enable2faUrl returnUrl, with the label "Continue to checkout" when it is set. Pass it to the Sign-in link (line 81) too, so the other-browser path also returns to Pricing after login. Leave the Ads conversion script untouched.

3. On /Pricing, read `?plan` and `?period` against a whitelist (falcon or eagle; m or y). Set the billing toggle to match. Show a "Continue with Falcon (monthly)" banner or highlight the button, and open Paddle on that click. Do not auto-open the checkout on page load.

4. Keep the existing `P.managed` check first. A user who already subscribes must still go to the portal, never to a second checkout.

## 17. [account] Submitting without ticking the captcha (or after it expires) costs a full round trip and wipes both password fields
- Severity: medium · kept 2/2 · owner: Finch (Majid only if new captcha keys are needed) · live site: yes · effort: 30 minutes for the button gating; 2-3 hours for a Turnstile swap
- Evidence: Views/Account/Register.cshtml:47-49 is a plain <div class="g-recaptcha" data-sitekey=…> with no data-callback or data-expired-callback, and :69 loads api.js only. grep finds no 'grecaptcha' anywhere in Views, so nothing in the browser stops a post without the tick. AccountController.cs:199-210 then answers ModelState.AddModelError("", "Please verify that you are not a robot."); return View(model);. The view uses Html.PasswordFor (:34, :43), which never re-fills a value, so Password and Confirm password come back empty and the captcha resets. The model's own comment (AccountViewModels.cs:112-114) calls a server-side bounce "the single biggest avoidable drop-off on this form", but only the password rule was moved into the browser.
- Impact: The one real visitor who opened Register overnight left without submitting (why is unknown). Any visitor who misses the tick, or whose 2-minute token expires, has to retype two passwords and solve a new captcha. That is a common point to give up, worse on a phone keyboard. Whether captcha image challenges appear more often in the Facebook/Instagram in-app browser is unknown.
- Fix: Disable "Create account" until data-callback fires, disable it again on data-expired-callback, and show a line "Tick 'I'm not a robot' to continue". Better: drop the visible step by switching to Cloudflare Turnstile in managed/invisible mode, which is already wired for the contact form (Controllers/ContactController.cs:67-69 _turnstile.VerifyAsync). New keys, if needed, are Majid's.
- Reviewer correction: Finch, live site, about 30-45 minutes. Add a client-side captcha check in Register.cshtml that runs after jquery-validation, so the form never posts without a token:
- In a submit handler, call `$(form).valid()` first. Then, if `typeof grecaptcha === 'undefined'` or `grecaptcha.getResponse() === ''`, call preventDefault and show an inline line next to the widget: "Tick 'I'm not a robot' to continue". If the script never loaded, show "The robot check didn't load. Turn off content blockers or try another browser".
- Add `data-expired-callback="fbCaptchaExpired"`, defined as a global function, that shows "The robot check expired. Tick it again". The token is valid for about 2 minutes.
- Keep the button enabled, so a visitor whose captcha script was blocked still gets an explanation rather than a dead button.
- Leave the server's fail-closed check as it is.

Optional extra (about 15 minutes): on a captcha refusal, add a specific ModelState error on the Password field ("Re-enter your password") so the emptied fields are explained.

Turnstile swap (2-3 hours, Finch, plus Majid for keys): only with a fail-closed path. Register must refuse when Turnstile:SecretKey is missing, not call the shared VerifyAsync, which returns true when disabled. Check first whether the Turnstile keys are set on production; that is unknown. The privacy policy already names Turnstile for the sign-up page (Privacy.cshtml:170), so no legal copy change would be needed. | Keep reCAPTCHA v2 and leave the server check unchanged. In Register.cshtml:
1. Add `data-callback="fbCaptchaOk" data-expired-callback="fbCaptchaExpired"` to the `.g-recaptcha` div.
2. Add a small hidden line under the widget, for example "Tick 'I'm not a robot' to continue."
3. Add a submit handler on the form that runs only after jquery-validation passes. If `window.grecaptcha` exists and `grecaptcha.getResponse()` is empty, cancel the submit, show that line and scroll to the widget. If grecaptcha never loaded, let the post go through; the server still refuses it, so nothing is weakened.
4. In fbCaptchaExpired, show "The check expired, please tick it again."
5. Do not disable the button.

This changes only the live Register page (production after a swap). Owner: Finch. Effort: about 30-45 minutes, plus a check on a phone.

Do not move registration to Turnstile unless the Turnstile site key and secret are confirmed set on both slots, and the registration path refuses a sign-up when Turnstile is not configured. Today Turnstile.VerifyAsync returns true when the secret is unset. Keys and the move itself are Majid's call; effort is about 2-3 hours once keys exist.

Optional: in the server-side captcha refusal, render a clearer message such as "Please tick 'I'm not a robot' and re-enter your password." Never re-fill the password fields.

## 18. [account] The Ads sign-up conversion can rarely fire, and the label setting is documented as unset
- Severity: medium · kept 2/2 · owner: Wren (Ads console), Majid (go for prod setting), Finch (server-side capture) · live site: yes · effort: 15 minutes for console + setting; 3-6 hours for server-side capture/import
- Evidence: Views/Account/ConfirmEmail.cshtml:20-24 + :87: the conversion is sent only when GoogleAds:ConfirmSignupLabel is set and well-formed (fail-safe off). CLAUDE.md:109 records "GoogleAds__ConfirmSignupLabel is UNSET … records zero conversions", with no later entry saying it was set; the live value is unknown. Views/Shared/_GoogleTag.cshtml:18-21, 64-66: gtag does not exist until the visitor accepts cookies in that browser. AccountController.cs:444-447: it fires on the confirmation page, i.e. in whatever browser opened the email link. The gclid hand-over (_GoogleTag.cshtml:67-80) only rewrites same-tab <a> links, so an email link never carries the ad click ID. AuthController.cs:933 vs :974: an unconfirmed account can still connect a PC in the app, so real activation can happen with no conversion at all.
- Impact: Google Ads shows 0 conversions for SAR 114. Even after real sign-ups start, conversions will be undercounted or not attributed to the click: a different browser, no cookie consent there, or the label unset. Smart bidding then cannot learn which clicks bring sign-ups, so ad spend cannot be judged or tuned.
- Fix: (1) Wren: in Google Ads, check that the 'Sign-up confirmed' conversion action exists and copy its label. (2) With Majid's go, set App Service GoogleAds__ConfirmSignupLabel on production (no redeploy). (3) Finch: save gclid/gbraid/wbraid server-side at registration (a hidden field carried from the landing URL into the Register form) and send conversions to Google from the server on email confirmation and on first PC connected (offline conversion import / enhanced conversions). That way the conversion no longer depends on the browser that opened the email. A second 'sign_up' event on CheckInbox, in the ad-click browser, is a cheap interim.
- Reviewer correction: 1. **Wren (Ads console, no live-site change, 15 minutes):** create or confirm a primary "Sign-up confirmed" conversion action and copy its label.
2. **Majid's go, production:** set `GoogleAds__ConfirmSignupLabel` on the production slot as a sticky setting (`az webapp config appsettings set --slot-settings @file`). It needs no redeploy, but the write restarts production for about a minute. Put the same value on staging too, so no swap can move it. Then check that `/Account/ConfirmEmail` from a real test sign-up emits the conversion after Accept.
3. **Finch, carry the click id through the form (about 1 hour, needs staging then a production deploy):** add a hidden field to the Register form with gclid/gbraid/wbraid from the page URL. Then CheckInbox and the confirmation flow can attribute the click when the visitor accepts cookies later in the same browser.
4. **Server-side conversion upload (offline conversion import or enhanced conversions, 3-6 hours, Finch):** do this only for visitors whose recorded consent at registration was 'granted'. Store that consent state with the gclid, and skip the upload for 'denied' or no choice. Majid must approve an update to the privacy policy, which must disclose server-side conversion upload before it ships. Without both, the policy's "nothing is sent to Google Ads" promise is broken.
5. **Optional interim:** a sign_up event on CheckInbox, set up in Google Ads as a secondary conversion that bidding does not use, de-duplicated so refreshes and resends do not count twice.
6. **Separate decision, Majid with Finch:** should the app's device sign-in (api/auth) refuse an account that has not confirmed its email, as the web login does? Today those people activate with no conversion at all. Refusing them would add friction and could itself cost activations, so it should not be changed casually. | Steps 1 and 2 stay as proposed:
1. Wren: in Google Ads, create or confirm the "Sign-up confirmed" conversion action and copy its label.
2. With Majid's go, set the production App Service setting GoogleAds__ConfirmSignupLabel. No redeploy is needed; it is about 15 minutes.

Step 3, replaced with a consent-safe version:
3a. Finch: add hidden gclid, gbraid, wbraid and consent fields to the Register form. Fill them from the landing URL or the carried links, and from localStorage fb-consent at submit. Store them on the user only when consent is "granted"; otherwise drop them. Under that rule the privacy text needs no change, but Majid confirms the wording because it is legal. Effort: 1-2 hours.
3b. Report confirmed and first-PC-connected conversions for consented users only. Cheapest route: an admin CSV export of gclid, conversion name and time, which Wren uploads by hand in Google Ads (Conversions > Uploads), for example weekly. A Google Ads API integration can come later, once Majid sets up a developer token and OAuth.
3c. Optional: a CheckInbox "sign_up" event, sent only when consent exists, and only as a SECONDARY (observation-only) conversion action so Ads does not bid on unconfirmed registrations.

Step 4: Finch logs a "first PC connected" timestamp at AuthController.cs:956, the AddDevice call on device sign-in. That gives a server-side activation count whatever the consent state, without sending anything to Google.

What changes on production: only the setting in step 2 and the Finch code once it is promoted. The rest is staging or the Ads console.

## 19. [account] No Google/Microsoft sign-in, and simply switching it on would create accounts that cannot sign in on the PC app
- Severity: medium · kept 2/2 · owner: Finch + Swift; Majid for the Google OAuth client · live site: yes · effort: 2-4 days
- Evidence: Login.cshtml and Register.cshtml show no external-provider buttons. grep finds no view that renders _ExternalLoginsListPartial. Program.cs:203-257 adds Google/Facebook/Microsoft only when their keys are configured (production config unknown). AccountController.cs:1162-1185 ExternalLoginConfirmationAsync creates an account from a free-text model.Email with CreateAsync(user), i.e. no password and the email not verified. AuthController.cs:930: the Windows app's /api/auth is PasswordSignInAsync only.
- Impact: A one-tap Google sign-in would remove the password, confirm-password, captcha and email-confirmation steps, which is the bulk of the friction, especially on phones. But with the current code, an account created through Google has no password and could never sign in on the Windows app. The free-text email step would also let someone claim an address they do not own.
- Fix: Treat this as a project, not a settings change. Use the provider's verified email claim (set EmailConfirmed, no free-text email), add the Terms line, and fire the conversion on account creation. Also give password-less accounts a way to connect a PC: a browser hand-off or device-code sign-in in the Windows app (Swift), or ask them to set a password before first app sign-in. The Google OAuth client and consent screen are Majid's (account).
- Reviewer correction: Do not enable any provider key in production until the code is fixed. Enabling it is a LIVE-site change. Finch fixes the code first, staging only:

1. In ExternalLoginCallbackAsync, ExternalLoginSignInAsync is called with bypassTwoFactor: true (AccountController.cs:1134-1138). A 2FA account that has an external login linked would skip TOTP entirely. Pass false.
2. In ExternalLoginConfirmationAsync, take the email from the provider's verified email claim (Google's email_verified). Do not use a free-text field. Set EmailConfirmed only when the provider vouches for the address. Refuse or merge carefully when that email already belongs to a password account, rather than creating a duplicate.
3. Add the Terms/Privacy line to ExternalLoginConfirmation.cshtml.
4. Fire the Ads conversion on account creation on this path. Today it fires only in ConfirmEmail.cshtml, which an external sign-up never reaches.
5. After an external sign-up, send the user to Manage → Set password, with copy saying the Windows app needs it. The Set password button already exists (Manage/Index.cshtml:88). The cheap interim is that prompt. A browser hand-off or device-code sign-in in the Windows app (Swift) is the proper fix, but it is a separate multi-day project.
6. Note that api/auth does not check EmailConfirmed. Close that before relying on unverified external emails.

Prefer Microsoft sign-in alongside Google, because Google blocks in-app webviews and the product is Windows-only.

Majid creates the OAuth client and consent screen (account). Effort: about 1 day of web work for items 1-5, then provider setup. Priority: below the landing → /Download → Register drop, which is where the measured visitors are lost. | Treat this as a Google-only project first. Microsoft and Facebook email claims are less reliable.

Web (Finch):
1. In ExternalLoginCallbackAsync, create the account from the provider's own email claim, and only when Google says the address is verified (email_verified true). Set EmailConfirmed=true and drop the free-text email page.
2. If an account with that email already exists, do not auto-link it. Ask the person to sign in with their password, then link Google from Manage → ManageLogins.
3. Change bypassTwoFactor to false so a linked Google sign-in cannot skip Folderbird's 2FA.
4. Add the Terms line to the Google button.
5. Fire the Google Ads conversion when the account is created through Google, because these accounts never reach ConfirmEmail.
6. Render the provider buttons on Login and Register only when a provider is configured. Today nothing renders them even if keys are set.

Windows app: v1 needs no Swift change. After a Google sign-up, and on the Download page for accounts without a password, show a "Set a password to connect your PC" step that links to the existing Manage/SetPassword page. A browser hand-off or device-code sign-in in the Windows app (Swift) can come later as an improvement.

Majid: create the Google OAuth client and consent screen, then set Authentication__Google__ClientId and Authentication__Google__ClientSecret as App Service settings (staging first). Setting the keys is what turns the feature on in production.

Effort: about 1-2 days for the web half; the Windows app work is optional.

## 20. [account] The form asks for a name it only uses for a greeting, plus a confirm-password field
- Severity: low · kept 2/2 · owner: Finch · live site: yes · effort: 30-60 minutes
- Evidence: Views/Account/Register.cshtml:26-30 "Your name" and :41-45 "Confirm password". Models/AccountViewModels.cs:128-130 [Required(ErrorMessage = "Please enter your name.")] public string Hometown. The name is only used for the navbar greeting (Views/Shared/_LoginPartial.cshtml:7 "Hello " + GetHomeTownByID) and the admin user list (AdminController.cs:380).
- Impact: Every extra required field on a phone keyboard drops some visitors. Two of the four fields add no value to the product at sign-up.
- Fix: Make the name optional (or remove it and ask later in Manage), and replace Confirm password with a show-password eye on the single field. If Confirm password is removed, keep the RegularExpression rule on Password.
- Reviewer correction: Owner: Finch. Effort: about 1-2 hours including tests. The change reaches staging when pushed to main and production only after a swap.

1. If the name field is dropped or made optional, first make `LightHouse.GetHomeTownByID` null-safe: `HomeTown = reader.IsDBNull(0) ? "" : reader.GetString(0);`. Also let the navbar label (`_Layout.cshtml:493`, `AlternateHome.cshtml:805`) fall back to the email or "Account" when the name is empty.
2. In `AccountController.RegisterAsync` (around line 217), never save NULL. Use `Hometown = string.IsNullOrWhiteSpace(model.Hometown) ? model.Email.Split('@')[0] : model.Hometown.Trim()`.
3. Only promise "ask later" if a name field is actually added to Manage. Today there is none.
4. To drop Confirm password, delete the `ConfirmPassword` property and its `[Compare]` from RegisterViewModel together with the view block (Register.cshtml:41-45). Otherwise every POST fails validation.
5. Add a show-password toggle on the single field. Keep the `[RegularExpression]` and `[StringLength]` rules on Password. Update the Scripts comment that mentions "matching confirmation".
6. Update `tests/pre_ads_copy_tests.js` (section D), and click-test a full registration on staging before swapping: submit, confirm the email, and open /Device to check there is no 500 for an account with no name. | Owner: Finch. This changes the live site once swapped. Effort is about 1 hour, including a staging test.

1. Make `LightHouse.GetHomeTownByID` null-safe: `HomeTown = reader.IsDBNull(0) ? "" : reader.GetString(0);`. Also have the navbar in _Layout.cshtml:493 and AlternateHome.cshtml:805 show "Account" when the name is empty. This also protects accounts from the external-login path, which never required a name.

2. Remove the name field from Register, or make it optional. Either way, never store NULL. In RegisterAsync, set `Hometown = string.IsNullOrWhiteSpace(model.Hometown) ? model.Email.Split('@')[0] : model.Hometown.Trim()`, and drop the `[Required]` from Hometown.

3. Remove the ConfirmPassword input together with the `ConfirmPassword` property and its `[Compare]` attribute. In its place, add a show/hide button to the single Password field (`type="button"`, with `aria-label` and `aria-pressed`). Keep `[Required]`, `[StringLength]` and the `[RegularExpression]` rule on Password, and keep `_ValidationScriptsPartial`. A mistyped password can still be recovered: the user must confirm their email anyway, and ForgotPassword works once the address is confirmed.

4. Only add "change your name in Manage" if it is actually built. Do not promise it in copy until then.

5. Test on staging: register with no name and check that /Device loads and the navbar shows a fallback. Register with one password and check that the server accepts it.

## 21. [account] Registering an address that already exists says "Username … is already taken", with no resend or sign-in link
- Severity: low · kept 2/2 · owner: Finch · live site: yes · effort: about 1 hour
- Evidence: Views/Account/CheckInbox.cshtml:160 suggests "Wrong address? Create the account again". AccountController.cs:253-261 shows Identity's raw error.Description. No custom IdentityErrorDescriber exists (grep), so the text is the default "Username 'x' is already taken." Program.cs:85-86 AllowedUserNameCharacters (a-zA-Z0-9-._@+) also rejects valid addresses with ' or non-ASCII characters as "Username … is invalid", after the captcha has been spent.
- Impact: Someone whose confirmation mail went astray and who tries again with the same address gets a message about a "username" they never chose. The passwords are wiped and there is no path to resend or sign in, so they are likely to give up.
- Fix: On DuplicateUserName for an unconfirmed account, resend the link (through TryTakeResendSlot) and redirect to CheckInbox with the address. This reveals nothing new, since today's message already shows the account exists. For a confirmed account, say "An account with this email already exists" with Sign in / Forgot password links. Plain wording for the invalid-characters case.
- Reviewer correction: The direction is right, but one safety rule is missing. On the duplicate path, do NOT mint the fb.reg cookie (RegisterBrowserCookie). That cookie is what stops a squatter from registering someone else's address and having the real owner confirm it and land inside an account whose password the squatter knows. Minting it here for an existing account would bring that hole back.

Concretely, in RegisterAsync before the generic error loop, when result.Errors contains Code == "DuplicateUserName":
- Look the account up with FindByNameAsync(model.Email).
- If it is unconfirmed: call TryTakeResendSlot(user.Id, now) and, if granted, SendConfirmationEmailAsync(user). Set TempData[PendingEmailKey] = model.Email and redirect to CheckInbox, with no fb.reg cookie. ConfirmEmail then shows "Sign in to continue", which is correct.
- If it is confirmed: add one model error such as "An account with this email already exists." Show contextual Sign in (asp-action Login) and Forgot password links next to it, through ViewBag rather than raw HTML in ModelState.
This reveals no more than today's message already does.

For InvalidUserName, stop it BEFORE the captcha is spent. Either add a client-and-server [RegularExpression] on RegisterViewModel.Email that matches AllowedUserNameCharacters, with plain wording ("Email addresses with apostrophes or accented letters aren't supported yet"), or add ' to AllowedUserNameCharacters. Before widening the character set, check every place UserName/Email is placed into a URL, SQL or an HTML attribute; the risk of that is unknown.

A shorter alternative is an IdentityErrorDescriber subclass that overrides DuplicateUserName and InvalidUserName with email wording. It is about 15 minutes of work but adds no resend path.

Owner Finch. This changes the live site after a swap. Effort about 1 hour, plus a staging test of both branches. | Keep the idea, but change the two-branch design and add three safeguards.

1. **Send one answer whether or not the account is confirmed.** The proposed fix sends unconfirmed accounts to CheckInbox and tells confirmed accounts "already exists, sign in". That lets anyone learn, without a password, whether an address is confirmed. Login deliberately hides that until the password is proven (the 2026-09-17 design: "registered but unconfirmed is not enumerable anonymously"). Instead, on `DuplicateUserName`:
   - Unconfirmed account: resend through the same `TryTakeResendSlot` + `SendConfirmationEmailAsync` path that `ResendConfirmation` uses.
   - Confirmed account: send nothing.
   - In both cases, redirect to CheckInbox (address in TempData, never in the URL) with the same copy: "This email already has a Folderbird account. If it still needed confirming, we've sent the link again. Already confirmed? Sign in, or reset your password." Link Login and ForgotPassword.

2. **Do not mint the `fb.reg` cookie on this path.** It exists to bind sign-in to the browser that created the account.

3. **Say the new password was not saved.** The password typed the second time is thrown away, so someone who chose a different one will fail at sign-in after confirming. The page should say "use the password you chose when you first registered, or reset it".

4. **Add a custom `IdentityErrorDescriber`** (or map by `error.Code` in `RegisterAsync`) so "username" never reaches the visitor:
   - `DuplicateUserName` / `DuplicateEmail`: handled as above.
   - `InvalidUserName`: "Folderbird can't accept this email address yet. Please use one with only letters, numbers and . _ - + characters."

   Ideally, also add a client-side `RegularExpression` to `RegisterViewModel.Email` that matches `AllowedUserNameCharacters`, so the address is refused before the captcha is spent. Do not widen `AllowedUserNameCharacters` as part of this change: user names are used in many lookups.

Owner Finch. It reaches production only after the usual staging then manual swap. About 1-2 hours including a test.

## 22. [account] On iPhone, each sign-up field zooms the page on tap
- Severity: low · kept 2/2 · owner: Finch · live site: yes · effort: 10-15 minutes
- Evidence: Register.cshtml:22, 28, 34, 43 (and Login.cshtml:37, 43) use form-control-sm. wwwroot/lib/bootstrap/bootstrap.min.css sets .form-control-sm{…font-size:.875rem…} (14px). Views/Shared/_Layout.cshtml:51 viewport is width=device-width, initial-scale=1.0 and there is no mobile override. iOS Safari zooms on any input smaller than 16px. Whether the Facebook/Instagram iOS in-app browser does the same: unknown.
- Impact: On iPhones the page zooms in on every field, pushing the captcha and Create account button off screen, so the visitor has to pinch back out. Small, but it hits most of the ad traffic, which is on phones.
- Fix: Use form-control (1rem/16px) on the Register, Login and CheckInbox inputs, or add @media (max-width:576px){.form-control-sm{font-size:16px}} in _Layout.
- Reviewer correction: The fix is right but needs narrowing. Remove `form-control-sm` from the seven inputs: Register.cshtml lines 22, 28, 34 and 43, Login.cshtml lines 37 and 43, and CheckInbox.cshtml line 46. Plain `.form-control` is 1rem, which is 16px. If the compact look must stay on desktop, add `@media (max-width:575.98px){.form-control-sm{font-size:16px}}` to _Layout instead. Note that this rule also changes every other -sm input on the site at phone width, so check those pages too. Do not fix it by adding maximum-scale=1 or user-scalable=no to the viewport: that blocks pinch-zoom, which hurts accessibility. Owner: Finch. It changes production after a deploy and swap. About 10-15 minutes, plus one test tap on a real iPhone. | Swap `form-control-sm` for plain `form-control` (1rem = 16px) on the inputs of the Account views: Register.cshtml lines 22, 28, 34 and 43, Login.cshtml lines 37 and 43, CheckInbox.cshtml line 46, and the inputs in ForgotPassword.cshtml and ResetPassword.cshtml. Do not use a max-width:576px media query: iPads are wider than that and still zoom, and the rule would change every small input on the site. Do not add maximum-scale=1 or user-scalable=no to the viewport either: that blocks pinch-zoom, which is an accessibility regression. Check the result in an iOS Safari or WebKit mobile emulation at 390px wide, in both themes. Owner: Finch. It changes the live site after the usual staging deploy and swap. Effort: about 15-20 minutes including that check. Priority: low, behind the other funnel findings.

## 23. [account] A broken or truncated confirmation link shows a bare "Error." page with no resend
- Severity: low · kept 2/2 · owner: Finch · live site: yes · effort: 15 minutes
- Evidence: AccountController.cs:387-396: a missing userId/code or unknown user returns View("Error"). Views/Shared/Error.cshtml says "Error. An error occurred while processing your request. Go to My Devices page". There is no CheckInbox or resend there, unlike the expired-token path at :420-423. Whether that view renders correctly at runtime (its @model is System.Web.Mvc.HandleErrorInfo) is unknown.
- Impact: A mail client that cuts or wraps the long link leaves the person on an alarming error page with no next step except My Devices, which sends them to Sign in.
- Fix: For missing or garbled parameters, redirect to CheckInbox with Expired=true and the email box, the same as the invalid-token path.
- Reviewer correction: For an empty userId or code, and for an unknown user, set TempData[ConfirmExpiredKey] = true and return RedirectToAction(nameof(CheckInbox)). Do NOT set PendingEmailKey here, and do not look up or show an address from a bare userId. With no address, CheckInbox already shows an email input ("The address you registered with") above the resend button. The expired banner text ("That confirmation link has expired or is no longer valid") fits these cases too. ResendConfirmation answers the same whether or not the address exists, so this leaks nothing about accounts.

Optional, separate change: the existing invalid-token path (line 422) shows user.Email to anyone who has the userId GUID plus any garbage code. That exposure is minor because GUIDs are not guessable, but it is the same pattern and worth not copying.

Owner: Finch. The change is to production web code: it goes to staging on the push to main, and reaches the live site only after a swap. Effort: about 10 minutes plus a click-test on staging with a hand-made broken link: drop &code=, and change one character of the userId. | In ConfirmEmailAsync, handle the two broken-link cases separately and replace both return View("Error") calls.

1. Missing or unknown user (userId empty, or FindByIdAsync returns null): set TempData[ConfirmExpiredKey] = true without setting PendingEmailKey, then return RedirectToAction(nameof(CheckInbox)). The CheckInbox view already shows a typed email box when Email is empty, and ResendConfirmation already gives the same answer whether or not the address exists, so this reveals nothing new.

2. User found but code empty: do the same as the invalid-token branch. If the email is already confirmed, set ViewBag.State = "confirmed" and return View("ConfirmEmail"). Otherwise set TempData[ConfirmExpiredKey] = true and TempData[PendingEmailKey] = user.Email, then redirect to CheckInbox. Do not show a resend box for an account that is already confirmed: the resend would quietly do nothing.

Owner: Finch. This changes the live site after the staging deploy and swap. Effort: about 15-20 minutes, plus one manual check of each case on staging.

## 24. [app] The Windows app has no 'Create account' or 'Forgot password' path: a person who installs without an account is stuck
- Severity: high · kept 2/2 · owner: Swift (app code); Majid runs the signed release (publish-release.ps1, password + OTPs); Finch moves the DownloadController Win*/Setup* constants · live site: yes · effort: 2-3 hours code, plus one signed release cycle (~1 hour for Majid) and a constants deploy + swap
- Evidence: LoginForm.Designer.cs:33-48: the only controls are lblSubtitle "Connect this device to your account" (line 77), txtEmail, txtPassword, chkShowPassword, chkRemember, btnLogin "Sign In" (line 201), lblFooter and errorProvider. No LinkLabel, no URL. InfoForm.cs:177-182: the only signed-out action is app.ShowLoginForm(). InfoForm.cs contains no Process.Start and no folderbird.com link. MyCustomApplicationContext.cs:496: "Sign in to make this device accessible." LoginForm.cs:144-149: someone with no account gets "Incorrect email or password. Please try again." The rest of the funnel sends people here first: AlternateHome.cshtml:835 and 1249, primary CTA "Start on the Download page" -> /Download.
- Impact: Install-first is the main path from the ads. The people with the most intent (they ran an installer) meet a sign-in wall with no way forward, and the only hint they get is a misleading 'incorrect password'. It matches the overnight numbers: 3 installer downloads, 0 sign-ups.
- Fix: In LoginForm, add a LinkLabel under the Sign In button: 'No account? Create one free', which opens https://folderbird.com/Account/Register?src=app through Process.Start(new ProcessStartInfo(url){UseShellExecute=true}). The same pattern is already used for ms-settings at MyCustomApplicationContext.cs:610. Add 'Forgot password?' -> /Account/ForgotPassword (the route exists, AccountController.cs:489). In the LoginFailed case, add 'No account with this email? Create one'. In the signed-out status window, add a second button 'Create free account' next to Sign In, or open LoginForm directly on a first run with no saved token. Tell the user they can sign in to the app straight after registering, because the server does not require email confirmation for the app (web Program.cs:90). Ship as 1.2.8.2: Swift writes it, Majid signs it with publish-release.ps1, Finch moves the seven DownloadController constants.
- Reviewer correction: Windows app (Swift), released as 1.2.8.2:

1. **Sign-in window.** In LoginForm, below Sign In, add a LinkLabel: "New to Folderbird? Create a free account". It opens https://folderbird.com/Account/Register through `Process.Start(new ProcessStartInfo(url){UseShellExecute=true})`, wrapped in try/catch and logged with LogCrash, the same pattern as the ms-settings call at MyCustomApplicationContext.cs:610. Add a second link, "Forgot password?", to https://folderbird.com/Account/ForgotPassword (the route exists, AccountController.cs:489). Add `?src=app` only if someone also logs it on the server. `Register()` ignores it today.
2. **Failed and locked-out sign-in.** Change the `LoginFailed` text to "Incorrect email or password. New to Folderbird? Create a free account (link) or reset your password (link)." Keep it neutral: the same reply comes back whether or not the address has an account, so the text must not hint at which. In `LockedOut`, make the forgot-password link visible.
3. **Signed-out status window.** Add a "Create free account" button next to Sign In.
4. **First run.** When there is no saved token, open LoginForm directly instead of only showing the tray balloon.
5. **After registering.** The app's text should tell people to confirm their email, then sign in here. Do not tell them they can skip confirmation. The website will not sign them in until they confirm, and that is where they browse their files. Confirmation is also where the Google Ads conversion fires.
6. **Testing.** Check the layout at 100%, 150% and 200% scaling. The form is FixedSingle, 404x404, with AutoScaleMode Font, so either make it taller or move lblFooter down.

Release (Majid runs `publish-release.ps1`, with his password and the three one-time codes):

7. Bump AssemblyVersion and AssemblyFileVersion together.
8. Follow the documented arming order:
   - set `AgentUpdate__Enabled=false`;
   - Finch moves all seven `DownloadController` Win*/Setup* constants, pushes, checks staging serves the new file, then swaps (this changes production);
   - re-download the zip from production and re-sign the manifest (`sig` + `msig`) against those bytes;
   - write the seven `AgentUpdate__*` settings as sticky slot settings;
   - set `Enabled=true`, then re-check the update from a device's point of view.

   Never move `WinBlob` without the `AgentUpdate__*` settings.

Interim fix that needs no app release (Finch, web, needs a production swap): on the Download page, under the hero Windows button, add "Create your free account first: you sign in to the app with it", linking to /Account/Register. Today the only register link on that page is in step 2, below the fold.

Effort: about 2-3 hours of app code, plus one signed release (about 1 hour for Majid), plus a constants deploy, a manifest re-sign and a swap. The web interim fix is about 15 minutes. | App change (Swift), as proposed:
1. Under the Sign In button in LoginForm, add a LinkLabel "No account? Create one free". It opens https://folderbird.com/Account/Register with Process.Start(new ProcessStartInfo(url){UseShellExecute=true}). The ?src=app tag is harmless, because the Register GET ignores the query string, and it can be counted in the HTTP logs.
2. Add "Forgot password?", which opens /Account/ForgotPassword (AccountController.cs:489).
3. In the LoginFailed case, add "No account with this email? Create one free".
4. In the signed-out InfoForm, add a "Create free account" button.

Change to the copy: say "Create your free account at folderbird.com, then sign in here." Do not tell users they can sign in before confirming their email. That works today only because api/auth skips the confirmation check that the web LoginAsync enforces. Printing it would make the gap look intentional, and it lets an account with a mistyped, unconfirmed address enrol a PC. Whether that should stay open is a separate decision for Majid.

Optionally, in the same release, add a postinstall entry to the installer's [Run] section of tools/windows-installer/Folderbird.iss: "Create your free Folderbird account" (Flags: postinstall shellexec skipifsilent unchecked), opening the Register URL.

Release (this is the gap in the original plan):
- Bump AssemblyVersion and AssemblyFileVersion together to 1.2.8.2. publish-release.ps1 refuses the build if they differ.
- Majid runs publish-release.ps1 (password and OTPs).
- Do not move only the seven DownloadController Win*/Setup* constants. /download/windows is also the URL the auto-update manifest advertises, and the AgentUpdate__* settings (Version, Sha256, Sig, Msig) are tied to WinBlob. If WinBlob moves to 1.2.8.2 while the manifest still carries 1.2.8.1's hash, every device downloads bytes that fail the hash check, silently, every 6 hours.
- The safe order is:
  1. Disarm with AgentUpdate__Enabled=false and confirm /agent/latest.json returns 204.
  2. Move the constants, deploy, and swap.
  3. Run tools/windows-installer/arm-fleet-update.ps1 against the published bytes.
  4. Write all the AgentUpdate__* settings in one sticky write, then re-arm.
- This is a production change; it needs Majid's go.

Web-only stopgap (Finch, live site, about 30 minutes, no app release):
- Raise the existing "No account yet? Create one free" from step 2 of /Download into the hero, next to the Windows button, e.g. "New? Create a free account first".
- Add a line to Account/CheckInbox saying the user can now sign in to the Folderbird app on their PC.

Effort:
- App code: about 2 hours.
- Majid's signed release: about 1 hour.
- Constants deploy, swap and fleet re-arm: about 1 hour (Finch and Majid).

## 25. [app] Clicking Download on /Download starts the file and the page never asks the visitor to create an account
- Severity: high · kept 2/2 · owner: Finch · live site: yes · effort: 1-2 hours; live after deploy + swap (Majid's go)
- Evidence: Views/Download/Index.cshtml:159: hero <a class="dl-btn" id="fbHeroWin" href="@heroWin">Download for Windows</a>, where heroWin = /download/windows/setup (line 23). DownloadController.cs:110-136 returns the file itself (File(stream, ...)), so there is no thank-you page. The only account prompt is in step 2 below the hero: 'No account yet? <a href="/Account/Register">Create one free</a>' (line 185). The page script (lines 293-363) only handles the installer/portable toggle and adds nothing on click.
- Impact: The browser shows a download and the visitor's attention moves to the installer. The step that actually counts (an account, and the email confirmation that fires the Ads conversion) is never put in front of them. This is the quickest lever because, unlike the app fix, it needs no signed Windows release.
- Fix: On click of any Windows/Linux download link (#fbHeroWin and .dl-plat-btn), and only for signed-out visitors (User.Identity.IsAuthenticated is false), reveal a panel at the top: 'Your download has started. Next: create your free Folderbird account. You'll sign in to the app with it.' with an email field or a button to /Account/Register?src=download (opens in the same tab, so the download keeps going). Also add a one-line 'You'll need a free account' with a Create link right under the hero buttons.
- Reviewer correction: Show the prompt for the Windows links only: #fbHeroWin and every link whose href starts with /download/windows (/download/windows/setup and /download/windows). Do this only when the visitor is signed out (`!User.Identity.IsAuthenticated`, rendered into the page).

On click, do not call preventDefault, so the file download keeps going. Reveal a panel next to the button that was clicked, or scroll to it. A panel fixed at the top of the page would be off-screen when someone clicks the card buttons further down. The panel says: "Your download has started. Next: create your free Folderbird account — the app asks you to sign in with it." Add a button to /Account/Register?src=download in the same tab. Register() ignores the query, but the parameter shows up in the HTTP logs, so you can measure this path.

Also add a line that does not need JavaScript under the hero buttons: "You'll need a free account to sign in to the app — Create one". Leave the Linux links alone; the Linux beta page already does this.

Owner: Finch. Changes the live site only after a deploy plus a swap to production, which needs Majid's go. Effort: about 1 hour. Swift should separately add a "Create a free account" link to the Windows app's LoginForm, which needs a signed release. | Owner: Finch. Effort: 1-2 hours. This changes the live site, so it needs Majid's go to reach production. I could not tell whether a swap is currently allowed or whether it has to go by the hotfix route.

1. No-JS part, signed-out visitors only (`User.Identity?.IsAuthenticated != true`): add one line directly under `.dl-btnrow`: "You'll sign in to the app with a free Folderbird account. <a href=\"/Account/Register\">Create one now</a>". This is the cheapest and surest piece.

2. JS part, Windows links only:
   - Bind click handlers on `#fbHeroWin` and the two Windows `.dl-plat-btn` links (inside #fbWinSetup and #fbWinZip). Do not bind the Linux links, which open the /beta tester page rather than a file.
   - Do not call preventDefault, so the download still starts.
   - On click, reveal a panel at the top of `.dl-wrap` (or just under the hero) that says "Your download has started. Next: create your free Folderbird account — you'll sign in to the app with it." and holds a primary button to /Account/Register (an extra `?src=download` is optional and harmless).
   - Bind by element, not by href, because the hero button's href changes when the toggle switches to the ZIP.
   - Render the panel hidden server-side, and only for signed-out visitors.
   - Put the same panel or line on the Linux beta page separately if wanted.
   - Do not add an inline email field: Register needs a password and a reCAPTCHA, so a button is the right control.

## 26. [app] The installer's finish page offers only 'Start Folderbird now'; nothing about an account
- Severity: medium · kept 2/2 · owner: Swift (installer script, in the web repo under tools/windows-installer); Majid signs; Finch moves the Setup* constants · live site: yes · effort: 30-45 minutes, plus the signing/publish cycle
- Evidence: tools/windows-installer/Folderbird.iss:136: [Run] Filename: "{app}\{#AppExe}"; Description: "Start {#AppName} now"; Flags: nowait postinstall skipifsilent. This is the only post-install action. [Messages] (lines 110-111) overrides only WelcomeLabel2 (per-user install text). No FinishedLabel and no link to folderbird.com.
- Impact: The last screen the visitor reads before the app could set them up for the account step. Right now it says nothing, so they reach the sign-in form without an account.
- Fix: Add a second postinstall entry: Filename: "https://folderbird.com/Account/Register?src=installer"; Description: "Create my free Folderbird account (opens your browser)"; Flags: postinstall shellexec nowait skipifsilent. Gate it with a Check: function so it shows only when there is no saved sign-in under {localappdata}\Folderbird (fresh installs, not upgrades). Add a FinishedLabel: 'Next: sign in to the app with your Folderbird account. No account yet? Tick the box below.' Rebuild with build-installer.ps1 -Sign -Publish, then update SetupBlob/SetupSha256/SetupBytes. Best done in the same release as finding 1.
- Reviewer correction: Ship this in the next numbered Windows release, together with the sign-in window fix. Do not re-publish 1.2.8.1.

1. **Folderbird.iss changes.**
   - Add a second postinstall entry after line 136: `Filename: "https://folderbird.com/Account/Register?src=installer"; Description: "No Folderbird account yet? Create one free (opens your browser)"; Flags: postinstall shellexec nowait skipifsilent; Check: NoSavedSignIn`.
   - In [Code], define `NoSavedSignIn` as true only when both files are missing: `{localappdata}\Folderbird\host.dat` and `{userappdata}\folderbird\host.txt`. Use FileExists on the two files, not DirExists, because the app creates the folder on every run.
   - Under [Messages], add FinishedLabel and FinishedLabelNoIcons. Suggested text: "Next: sign in to the Folderbird app with your Folderbird account. No account yet? Leave the box below ticked to create one."
   - Optional: `?src=installer` is only useful if the Register action or analytics reads it. Otherwise drop it.
2. **Build and publish.**
   - Majid builds with `.\publish-release.ps1 -Version <next, e.g. 1.2.8.2>` (password plus three one-time codes). It refuses to overwrite an existing blob and builds the installer from the newly published zip.
   - Never run `build-installer.ps1 -Sign -Publish` on its own. Without `-Version` it packages the old 1.2.0.0 zip. With `-Version 1.2.8.1` it overwrites the live installer in place, so the served bytes stop matching the SHA-256 printed on /Download.
3. **Release constants.**
   - Finch moves all seven DownloadController constants together.
   - The AgentUpdate settings follow the normal arming order, because the app version changes.
4. **Ownership and timing.**
   - Swift writes the .iss change; Finch moves the constants; Majid signs and approves the production swap.
   - It reaches the live site only after that swap.
   - Effort: about 30 minutes of script work, plus the full release cycle. | 1. **Check for a saved sign-in in both places.** The Check: function must look for `{localappdata}\Folderbird\host.dat` and for the legacy `{userappdata}\folderbird\host.txt`. The agent reads both (Utils.cs:344-346, with migration on first read). The browser entry and the FinishedLabel text should show only when neither file exists. A reinstall keeps the sign-in by default (the uninstall prompt's suppressed default is IDNO, Folderbird.iss:199-201), so upgrades are covered.

2. **The browser entry.** Use `Filename: "https://folderbird.com/Account/Register?src=installer"; Description: "Create my free Folderbird account (opens your browser)"; Flags: postinstall shellexec nowait skipifsilent; Check: NoSavedSignIn`. Keep "Start Folderbird now" as the first entry.
   - `?src=installer` is ignored by `Register()` (AccountController.cs:147 takes no parameters). It is harmless and shows in the HTTP logs for counting.

3. **Do not republish at version 1.2.8.1.** `build-installer.ps1 -Publish` uploads with `--overwrite true` (build-installer.ps1:179). It would replace the already-published Folderbird-Setup-1.2.8.1.exe, whose SHA-256 and size are printed on /Download from DownloadController.cs:52-53. Until the new constants are deployed and swapped, production would serve bytes that do not match the hash on the page. Instead:
   - Ship the change with the next app version through `publish-release.ps1`. Majid has to run it himself (SSL.com password plus one-time codes).
   - Move all seven DownloadController constants together, deploy to staging, then swap to production.

4. **Order.** Fix the app's login form first: a "No account? Create one free" link opening /Account/Register, plus the same hint after a LoginFailed reply. Swift owns it, and it reaches both installer and ZIP users. Put the installer change in the same signed release.

Effort: about 30 minutes for the installer script and about 1 hour for the login form, plus the release cycle Majid runs. Production changes only when the release is published and swapped.

## 27. [app] Launching Folderbird from the Start menu shows no window when the app is not already running
- Severity: medium · kept 2/2 · owner: Swift; Majid signs the release · live site: yes · effort: 30 minutes code, plus the release
- Evidence: Folderbird.iss:126: the Start-menu shortcut has Parameters: "/startup". WindowsAppIdentity.cs:71: link.SetArguments("/startup") with the comment 'launching from the Start Menu behaves like autostart'. Program.cs:65-70 and 84: /startup means ShowWindowOnStart = false. MyCustomApplicationContext.cs:312: the window opens only if ShowWindowOnStart. The only signal is a tray balloon with a 1000 ms timeout (line 497).
- Impact: Anyone who unticked 'Start Folderbird now', closed the app from the tray, or comes back later and clicks Folderbird in Start sees nothing open, only a tray icon. They can easily think the app is broken and give up before ever reaching sign-in.
- Fix: In the app: when there is no saved token (Utils.LoadToken() is empty), open the sign-in window even under /startup. A never-signed-in PC then gets a visible prompt at launch and at each logon (the app registers the Run key at first start, line 233). Alternatively, remove /startup from the Start-menu shortcut in both Folderbird.iss:126 and WindowsAppIdentity.cs:71. The installer line governs new installs, because EnsureShortcut only rewrites a shortcut whose target differs.
- Reviewer correction: Owner: Swift. The .iss lives in the web repo's tools/windows-installer, so tell Finch about that one line. Majid signs and publishes the release, and the installer has to be rebuilt.

1. Folderbird.iss:126: delete `Parameters: "/startup";`. Keep AppUserModelID exactly as it is. This fixes new installs and reinstalls.
2. WindowsAppIdentity.cs: drop `link.SetArguments("/startup")` and update the comment. Also extend ShortcutTargetsCurrentExe so it reads the shortcut's arguments with IShellLinkW.GetArguments and returns false when they contain "/startup". EnsureShortcut then rewrites existing shortcuts, with the AUMID, on the next launch after the self-update, so the installed base is fixed too.
3. Leave the Run key and the scheduled task passing /startup, so logon and watchdog launches stay silent.

Optional, low risk: when no token is saved, make the NotLoggedIn balloon open the window on click (BalloonTipClicked is already wired to BalloonTipClickedAfterLoggedOut), and give it a longer timeout.

Effort: about 30 to 45 minutes of code plus the signed 1.2.8.x release. It reaches production users only through the next signed release and installer. Nothing changes on the website itself. | Recommended: make a Start-menu click behave as an explicit launch.
1. Remove `Parameters: "/startup"` from Folderbird.iss:126. This is in the web repo under tools/windows-installer; it changes only the installer that gets built and published.
2. Drop `SetArguments("/startup")` from WindowsAppIdentity.cs:71.
3. Extend ShortcutTargetsCurrentExe so it also reads IShellLinkW.GetArguments and treats a shortcut that has /startup as needing a rewrite. Without this, existing installs keep the silent shortcut forever. Keep the AUMID stamping as it is.
4. Optionally, also open the window under /startup when there is no saved token, but only once per logon. That gives a never-signed-in PC a visible sign-in prompt. Be careful: it changes autostart behaviour on every logon until the user signs in.

Owners:
- Swift: the app half (steps 2 to 4).
- Finch or the release flow: the .iss.
- Majid: signs the release.

Effect on the live site: none. The change reaches users only through a signed release (1.2.8.2 or later) plus auto-update and new installer downloads.

Effort: about 30 to 60 minutes of code, plus the release.

## 28. [app] A password containing " or \ can never sign in to the Windows app (raw string JSON); the error says the server can't be reached
- Severity: medium · kept 2/2 · owner: Swift (app); optional server null-guard by Finch · live site: yes · effort: 30 minutes, plus the release
- Evidence: LoginForm.cs:119-127 builds the body by concatenation: " \"userpassword\": \"" + txtPassword.Text + "\",". It does no escaping. The website accepts such passwords: AccountViewModels.cs:117 regex ^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{6,}$ allows any character, and web Program.cs:73 sets RequireNonAlphanumeric = false but forbids nothing. Server AuthController.cs:921 Post([FromBody] login login), then line 929 login.useremail with no null check. AuthController is a plain ControllerBase (line 38) and Program.cs has no UseExceptionHandler, so invalid JSON leaves login null and the request throws. The likely result is an empty 500, which the app shows as "Can't reach the server. Please try again." (LoginForm.cs:158-160). A sequence like \n or \t is valid JSON but changes the password, so the user gets "Incorrect email or password" and the failure counts toward lockout (10 attempts). The exact 500 body was not observed at runtime.
- Impact: A new user whose password manager generated a quote or backslash registers fine on the web and can then never connect their PC. The message they get blames the network. How many users are affected is unknown.
- Fix: Serialize the login body with a real JSON serializer (the DataContractJsonSerializer path already in Utils.ExecuteAPIMethod(object, Type, ...), Utils.cs:88-99, or a small escape for \ and ") instead of string concatenation. Apply the same to the email field. Optional server-side belt: if (login == null) return "LoginFailed" in api/auth.
- Reviewer correction: App (Swift): build the login body with Newtonsoft, which the app already references and uses in FileRouteClient/RestartReadiness.cs:84, instead of concatenating strings:

`JsonConvert.SerializeObject(new { useremail = txtEmail.Text.Trim(), userpassword = txtPassword.Text, devicename = Utils.DeviceDisplayName(), address = deviceAddress, agentversion = Utils.AppVersion(), devicecode = _deviceCode ?? "" })`

That escapes `"`, `\` and control characters in every field. The DataContractJsonSerializer overload (Utils.cs:88) also works, but it needs a named DTO with these exact lowercase member names. Add a test login with a password containing `"`, `\w` and `\n`. This needs a signed release (1.2.8.2 or later) and reaches installed PCs only through the fleet update.

Server (Finch, optional, changes production): at the top of AuthController.Post add `if (login == null || string.IsNullOrEmpty(login.useremail) || login.userpassword == null) return "LoginFailed";`. That answers before PasswordSignInAsync, so it adds no lockout count. Already-deployed apps would then show "Incorrect email or password" instead of a network error. That is still misleading, but it is not a 500. Do not try to repair the body server-side.

Effort: about 30 minutes of code and test in each repo, plus the signed Windows release. | **App (Swift):** in LoginForm.DoLoginAsync, build the body with a real serializer instead of concatenating strings. Newtonsoft.Json 13 is already referenced in Folderbird.csproj:114 and used in RestartReadiness.cs:84, so the change is `string JSONlString = JsonConvert.SerializeObject(new { useremail = txtEmail.Text.Trim(), userpassword = txtPassword.Text, devicename = Utils.DeviceDisplayName(), address = deviceAddress, agentversion = Utils.AppVersion(), devicecode = _deviceCode ?? "" });`. Then send it through the existing `Utils.ExecuteAPIMethod("/auth", JSONlString, true)`. This keeps the same field names, so no server change is required. Also escape the device name, because a profile-mode device-name.txt could contain a quote. Ship it in the next signed Windows release (1.2.8.2 or later) with the usual auto-update arming. It reaches devices only through that release.

**Server (Finch, optional):** at the top of the `api/auth` Post action, add `if (login == null || string.IsNullOrEmpty(login.useremail) || login.userpassword == null) return "LoginFailed";`. The app already recognises "LoginFailed", and any unknown string would be saved as the token. With this guard, deployed 1.2.8.1 apps show "Incorrect email or password" instead of a false network error. This change deploys to staging on the push to main and reaches production only on a swap.

**Effort:** about 30 minutes for the code, plus the release cycle. Changes only the Windows app, and the server only if the optional guard is taken.

## 29. [app] After a successful app sign-in, nothing takes the person to folderbird.com, where the product and the conversion-firing email confirmation are
- Severity: medium · kept 2/2 · owner: Swift; Majid signs the release · live site: yes · effort: 30-60 minutes, plus the release (bundle with finding 1)
- Evidence: LoginForm.cs:222-231: ShowMessage("Signed in. This device is now accessible.") then Close(). InfoForm.cs has no link and no Process.Start. The app accepts unconfirmed accounts (web Program.cs:90 RequireConfirmedEmail = false; AuthController.cs:929 PasswordSignInAsync), but the website blocks them until confirmed (AccountController.cs:99). The Ads conversion fires only on ConfirmEmail (ConfirmEmail.cshtml:99).
- Impact: A person who signed up from the app can stop right there: PC 'connected', but they never open the website, never see their files and never confirm the email. That loses the activation and the only counted conversion.
- Fix: Change the success state to 'Your PC is connected. Open it in your browser' with a button that opens https://folderbird.com/Device (the website then shows the confirm-email/resend form if needed). Put the same 'Open folderbird.com' link in the status window when Connected.
- Reviewer correction: Put the action in MyCustomApplicationContext.LoggedIn(), not in LoginForm's success label. LoginForm closes right after showing it, and LoggedIn() is called only from LoginForm.cs:228, so it runs only after a sign-in typed into the form, never on a restart with a saved token.

In LoggedIn():
1. Once per fresh sign-in, open the site in the default browser: Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }) inside try/catch.
2. Change the balloon to "Your PC is connected - click to open it in your browser" and attach a BalloonTipClicked handler that opens the same URL. Detach it in NotLoggedIn()/LogOut().
3. Add an "Open folderbird.com" tray menu item, and a link in InfoForm that shows while Connected.

The URL must follow the server the app talks to. In production use https://folderbird.com/Device. The app's own base URL is folderbird-app.azurewebsites.net, so use folderbird.com rather than stripping "/api" from it. In test-profile mode, build the URL from Utils.ProfileBaseUrl() minus "/api", so a staging tester is never sent to production.

What the person will see: Register does not sign the browser in, so /Device redirects to /Account/Login. After the password, an unconfirmed account sees the existing resend form (AccountController.cs:99-105). That is acceptable. A better follow-up is to say "check your inbox to finish setting up your account" in the same balloon. The app cannot tell whether the account is confirmed without a protocol change, so word it as a reminder ("If you haven't yet, confirm your email").

Owner: Swift. Ships in a signed release (Majid runs publish-release.ps1 and moves the seven DownloadController constants with the AgentUpdate__* settings). It reaches production for new installers only. Effort: about 1 hour of code, plus the release. | Owner Swift; Majid signs the release.
1. Replace the instant `Close()` after sign-in with a short success state: "Your PC is connected. Open it in your browser", with an "Open folderbird.com" button. The button runs `Process.Start(new ProcessStartInfo("https://folderbird.com/Device") { UseShellExecute = true })` inside try/catch and logs a failure with `LogCrash`.
2. Do not build the URL from `Utils._BASEURL`. In production that is folderbird-app.azurewebsites.net/api, which is not the site people use. Hardcode https://folderbird.com/Device for the normal install. Use the profile's own host only when `Utils.ProfileMode` is set, so a staging test copy never sends a tester to production.
3. Add the same link in two more places:
   - the status window (InfoForm) whenever the state is Connected;
   - a tray menu item "Open folderbird.com".
4. Hook `notifyIcon.BalloonTipClicked` to the same open action in `LoggedIn()`. Today line 528 leaves the balloon with no click action.
5. Leave the server untouched. Do not change the `api/auth` response or start requiring confirmation for device sign-in, because the app stores any non-error reply as its token. The website handles the rest on its own: /Device sends a signed-out visitor to Login, and Login shows the confirm/resend form to an unconfirmed account (AccountController.cs:99-106).

The website and the server are unchanged. The change reaches PCs only through a signed Windows release and the auto-update. Effort: about 1 hour of code plus the release; bundle it with the app's missing create-account link.

## 30. [app] No way to tell whether a download or an app launch leads to a sign-up
- Severity: low · kept 1/2 · owner: Finch (web); Wren (GA4/Ads console) · live site: yes · effort: 30-60 minutes web; 15 minutes console
- Evidence: The only gtag('event') in Views is ConfirmEmail.cshtml:99. The download buttons (Download/Index.cshtml:159, 223, 232) send no event. /download/windows(/setup) is a direct file response (DownloadController.cs:110-136), so there is no thank-you page to count. Register links carry no source parameter (Index.cshtml:185; AlternateHome.cshtml:814).
- Impact: Without this, nobody can confirm that findings 1-3 fix the 3-downloads / 0-sign-ups gap, and Google Ads optimises with no signal between click and confirmation. GA4 is consent-gated, so it undercounts too.
- Fix: Finch: add ?src=download / ?src=app / ?src=installer to every Register link those surfaces use. These land in AppServiceHTTPLogs whatever the consent choice. Add a consent-gated gtag('event','file_download',{file_name}) on the download buttons. Wren: check whether GA4 Enhanced measurement 'File downloads' is on (unknown from source) and consider importing it as a secondary conversion in Google Ads.
- Reviewer correction: If this is kept as low-priority measurement work, change nothing on the live site. Owner: Finch (or whoever maintains the daily report).

Add one saved query to the daily report (`.github/workflows/daily-report.yml`, with its twin `tools/telemetry/daily-visits.ps1`). It should take AppServiceHTTPLogs, production slot only, and join on client IP within 24 hours:
1. GET /download/windows*
2. GET /agent/latest.json (the app was started)
3. POST /api/auth (sign-in tried in the app)
4. GET /Account/Register
5. POST /Account/Register answering 302 (account created)
6. GET /Account/ConfirmEmail (address confirmed)

It should report counts only, never IPs. This measures the whole chain whatever the visitor chose on cookies, using data that already exists. Effort: about an hour. It touches CI only, not production.

Optional, also by Finch: a `file_download` gtag event on the four download buttons, behind consent, at about 20 minutes. Do not rely on GA4's automatic file-download tracking, because these links have no file extension.

A `?src=` tag on the Windows app's sign-in screen is only useful once Swift adds a "create account" link there. There is none today.

Drop the Wren task to check GA4's automatic file-download tracking: these links cannot trigger it. | Finch (web, reaches production on the next swap; about 1-2 hours):

(a) Add ?src=download to Download/Index.cshtml:185. Add ?src=landing to the landing page's Register links (AlternateHome.cshtml:814 and the hero/CTA links) and ?src=nav to _Layout.cshtml:501.

(b) Keep the tag through the POST so the 302 row is attributable. In Register.cshtml, change the form to Html.BeginForm("Register","Account", new { src = <src from the request, checked against a fixed allowlist such as download|landing|nav|pricing> }, FormMethod.Post, ...), or put the same value in a hidden field. Then a KQL query on AppServiceHTTPLogs (CsUriQuery) can count GET and 302-POST per src, whatever the consent choice.

(c) On the three download anchors, add a click handler that calls gtag('event','file_download',{file_name, link_url}) only if typeof gtag === 'function'. A plain handler on the anchor does not block navigation. Do not rely on GA4 Enhanced measurement: it matches by file extension and these URLs have none.

Swift (Windows app, needs a signed release): ?src=app only becomes possible once the app's sign-in window has a "Create an account" link. Add that link to folderbird.com/Account/Register?src=app as part of whichever finding adds it.

Wren (ad console, no site change; about 15 minutes): import the GA4 file_download event into Google Ads. Keep it SECONDARY (observation only) unless Majid decides to bid on downloads, because making it primary would optimise for downloaders rather than sign-ups. The ConfirmEmail conversion stays primary.

## 31. [app] The 2FA nudge on ConfirmEmail comes before the first PC, and turning 2FA on makes the app's first sign-in demand a device code
- Severity: low · kept 2/2 · owner: Finch · live site: yes · effort: 30 minutes
- Evidence: ConfirmEmail.cshtml:65-77 shows 'Add two-factor authentication ... Set it up' at the moment of confirmation. AuthController.cs:946-950: a 2FA account adding a NEW PC gets "NeedDeviceCode". The app then asks the user to go to folderbird.com, click 'Add a device' (DeviceList.cshtml:198) and copy a code from a window.prompt (DeviceList.cshtml:499).
- Impact: This doesn't lose the sign-up itself (the account exists). But a brand-new user who follows our own advice gets an extra trip back to the website on first run, at the point where they are most likely to drop off.
- Fix: Show the 2FA nudge only when the account already has at least one device, or add to it: 'Connect your PC first; turning this on later avoids an extra code step.'
- Reviewer correction: Keep the nudge, but say what it costs: "Connect your first PC before turning this on. With two-factor on, each new PC asks for a one-time code from folderbird.com." Optionally make "Not now" the main button, and show the 2FA offer again on /Device once the first device is online. That move needs a device-count check (LightHouse.GetUserDevicesList) in the view model, so budget about 1 hour with a test. Owner: Finch. The copy change is ~15-30 minutes and reaches the live site on the next swap to production. A later improvement is to replace the window.prompt in fbAddDevice with a proper copyable dialog. | Owner: Finch. This changes the live site: it is a Razor view, so it goes to staging on push to main and to production on swap.

Cheapest option, about 10-15 minutes, copy only: in ConfirmEmail.cshtml lines 70-77, add one line to the nudge. For example: "Best done after your first PC is connected. With it on, the Folderbird app asks for a one-time code from this site when you add a new PC."

Better option, about 30 minutes plus a staging check, conditional: in the `signedin` branch of AccountController.ConfirmEmail, set ViewBag.HasDevice from one Devices row-exists check by UserId (or LightHouse.GetUserDevicesList(user.Id).Count > 0). Render the nudge only when a device exists. When there is none, drop the nudge or replace it with the "download the app and sign in" next step, which is what this user actually needs. Re-offer 2FA on /Device once the first device appears.

Do not touch the Google Ads conversion script block at the bottom of that view. Do not change the AuthController gate either; it is the audit-#3 security control.

## 32. [tracking] The only Google Ads conversion sits behind a chain of conditions that phone sign-ups rarely meet, so even a real ad sign-up is unlikely to be counted or credited
- Severity: high · kept 2/2 · owner: Finch (code), Wren (Ads conversion actions + enhanced conversions), Majid (privacy wording sign-off, App Service setting go) · live site: yes · effort: Code 1-2 hours plus tests; console 15-30 minutes
- Evidence: Views/Account/ConfirmEmail.cshtml:87 `@if (adsLabelOk && !string.IsNullOrEmpty(confirmedUserId))`; lines 104-105 `if (typeof gtag === 'function') fbConversion(); else (window.fbAfterGtag = window.fbAfterGtag || []).push(fbConversion);`. gtag exists only after Accept in that browser (_GoogleTag.cshtml:66 `if (c === 'granted') window.fbLoadGtag();`). The queue is page-local (_GoogleTag.cshtml:45-47), so a visitor who clicks 'Sign in' / 'Go to my devices' without pressing Accept loses the conversion. ConfirmEmail is reached only from an emailed link (AccountController.cs:385-447). On phones that link opens in the mail app's or default browser, not in the Facebook/Instagram in-app browser or the tab the ad opened, so the first-party ad-click cookie and the 'fb-consent' choice are absent. No user_data (enhanced conversions) is sent anywhere: the conversion payload is only send_to + transaction_id (lines 99-102). Nothing fires at CheckInbox, which is in the same browser as the ad click (Views/Account/CheckInbox.cshtml has no script).
- Impact: Google Ads reports 0 conversions even when a sign-up happens, so Smart Bidding never learns which clicks produce sign-ups. It keeps paying for low-quality clicks, such as the Display placements counted as Search. With near-zero volume, losing even one real conversion leaves the campaign with no signal at all.
- Fix: 1) Add a second conversion action, 'Sign-up submitted', fired on CheckInbox only right after a successful registration. Set a one-shot TempData flag next to AccountController.cs:249, emit the same consent-guarded/queued gtag call as ConfirmEmail with transaction_id = user id, and add a separate setting such as GoogleAds__RegisterSignupLabel. This fires in the browser that holds the ad click. 2) Send enhanced-conversion data on both pages: `gtag('set','user_data',{email: <address>})` before the conversion (gtag hashes it client-side). This lets Google match the confirmation even when the email opens in another browser. CheckInbox already prints the address (CheckInbox.cshtml:27). 3) In Google Ads, create the 'Sign-up submitted' action and turn on Enhanced conversions for web (Wren). Keep 'Email confirmed' as the primary action once it has volume; use 'Sign-up submitted' as primary while volume is near zero (Wren/Majid choice). 4) Extend tests/consent_mode_tests.js for the new page. 5) Privacy §6 (Privacy.cshtml:146-148) already says Ads measures 'which advertisements led to a visit or a sign-up'. Whether sending a hashed email needs extra wording is Majid's call.
- Reviewer correction: Steps 0, 1 and 4 change only App Service settings or the Ads console, not the site code.

0. **Check the conversion is switched on first** (Majid or Wren, settings only, live site). Confirm GoogleAds__ConfirmSignupLabel is set on the production slot and matches a real 'Email confirmed' conversion action in Google Ads. If it is unset, nothing fires today, and none of the later steps matter until it is set.

1. **Add 'Sign-up submitted' on CheckInbox** (Finch, live site after swap).
   - Set a one-shot TempData flag only on the success branch of RegisterAsync, beside AccountController.cs:249.
   - Do not set it on the resend path (:373) or the expired-link paths (:421-422, :431-432). Those also land on CheckInbox.
   - Use the same consent-guarded, queued gtag pattern as ConfirmEmail. Put the label in its own setting, e.g. GoogleAds__RegisterSignupLabel, fail-safe while unset, with transaction_id = user id.
   - Ship it after Finch's malformed-email fix, so junk addresses are not counted.

2. **Add an installer-download micro-conversion** (Finch, live site). Fire a consent-gated gtag event when someone clicks the /download/windows/setup link on /Download, with its own label setting. Overnight there were 3 ad-driven installer downloads against 0 register submits, so this is the only step that gives signal at today's volume.

3. **Send enhanced-conversion data** (Finch, live site). Call `gtag('set','user_data',{email})` on both pages, immediately before the conversion event and inside the same queued function. ad_user_data is already granted on Accept (_GoogleTag.cshtml:36).

4. **Console work** (Wren, console only).
   - Create the new conversion actions.
   - Keep 'Sign-up submitted' and 'Installer download' as secondary (observation) actions, and keep 'Email confirmed' primary.
   - Make one of the new ones primary only if Majid chooses to, accepting that bidding then optimises for unconfirmed sign-ups.
   - Majid, as account owner, must accept Google's customer data terms before enhanced conversions can be turned on. He also signs off on whether Privacy §6 needs a line about sending a hashed email address.

5. Extend tests/consent_mode_tests.js to cover the new pages: no gtag call without consent, and the queued call runs after Accept on the same page.

Effort: code 1-2 hours plus tests; console 15-30 minutes. | 0) Wren or Majid, first, about 5 minutes, console only: confirm that the 'Email confirmed' conversion action exists in Google Ads, and that App Service GoogleAds__ConfirmSignupLabel is set on the production slot as a sticky setting. CLAUDE.md last recorded it unset. If it is unset, setting it is the whole fix for today and needs no redeploy.

1) Finch, about 1-2 hours plus tests, changes the live site after a swap:
- Add a 'Sign-up submitted' conversion on CheckInbox. Fire it only from a one-shot TempData flag set beside AccountController.cs:249, never on resend or expired-link visits.
- Use the same consent-guarded and queued gtag pattern, transaction_id = user id, and a new setting GoogleAds__RegisterSignupLabel that does nothing while unset.
- Carry gclid, gbraid and wbraid through the Register POST, so the CheckInbox URL still has the click id when the visitor accepts there. Two ways: add the click id to the BeginForm route values in Register.cshtml:15, or a hidden field that the controller puts on the CheckInbox redirect.

2) Enhanced conversions:
- On CheckInbox, `gtag('set','user_data',{email: ...})` is acceptable, because the page already shows the address.
- On ConfirmEmail, do NOT put the raw address in the page. Compute the normalised SHA-256 on the server (trim, lowercase) and send `{sha256_email_address: <hex>}`. Wren turns on Enhanced conversions for web in Ads. Majid decides whether Privacy §6 needs a sentence about sending a hashed email.

3) Optional, minutes: fire the conversion on the already-signed-in redirect path (AccountController.cs:438-441) too, or accept that it is lost.

4) Extend tests/consent_mode_tests.js to cover CheckInbox, and assert that no raw email appears in ConfirmEmail's output.

5) Note: in basic consent mode, a visitor who never presses Accept is never counted by any of these fixes. Moving to advanced consent mode, for cookieless pings and modelled conversions, reverses Decision I. That is Majid's call, not a code fix.

Primary or secondary action choice: Wren and Majid.

## 33. [tracking] Unknown whether GoogleAds__ConfirmSignupLabel is set in production; if it is not, the site emits no conversion at all
- Severity: high · kept 2/2 · owner: Wren (console check), Majid (production setting) · live site: yes · effort: 15 minutes
- Evidence: ConfirmEmail.cshtml:20 `var adsLabel = Cfg["GoogleAds:ConfirmSignupLabel"];` and :23-24 (must match ^[A-Za-z0-9_-]{1,64}$); :87 emits nothing when it is empty or malformed. appsettings.example.json:68-75 leaves it empty. The most recent repo record, CLAUDE.md:109, says 'GoogleAds__ConfirmSignupLabel is UNSET, so the tag measures page views and remarketing and records zero conversions' (dated 2026-09-17). No later entry records it being set. Its production value cannot be read from source: unknown.
- Impact: If it is unset, every confirmed sign-up from an ad is invisible to Google Ads, and the 0 conversions shown in Google Ads mean 'not measured' rather than 'none happened'. The setting also fails silently if someone pasted the whole snippet or the 'AW-.../label' form instead of the bare label.
- Fix: Wren checks Google Ads > Goals > Conversions: is there a sign-up action for AW-1017057167, what is its status (Inactive / No recent conversions / Unverified), and what is its label (the part after the slash in send_to). Majid, or someone with his go, sets App Service GoogleAds__ConfirmSignupLabel on the production slot to the bare label (sticky slot setting, no redeploy). Verify by viewing the source of a real confirmation page after accepting cookies (the send_to string appears), or with Google Tag Assistant.
- Reviewer correction: Keep the fix, with these corrections. (1) Wren checks Google Ads > Goals > Conversions for a sign-up action under AW-1017057167. Check its status, that it is a Primary goal, and that it counts "One" per click, then copy only the label (the text after the slash in send_to). If no action exists, Majid creates one (a website action, set up manually with code). (2) Majid's go is needed because this is a production change. Writing an App Service setting restarts the production app, and the Folderbird connector drops for about 30-60 s, so do it in a quiet minute. Set it on the production slot as a sticky slot setting (--slot-settings, using the @file form). Then read back the setting names with slotSetting=true. A non-sticky value moves to staging on the next swap, as happened to OpenAi__AppsChallengeToken. Put the label on staging as well, sticky, if staging should fire it too. (3) Verification as written is slightly wrong. The script block is rendered on the server whether or not cookies were accepted, so "send_to" shows in the page source either way. Consent only decides whether it runs. It also renders only on a valid confirmation link: a fresh link within 24 h, or a re-opened one within 24 h. A stale link on an already-confirmed account renders no conversion. Steps: register a throwaway account, open its confirmation link in a browser that accepted cookies, and confirm a request to googleadservices/googletagmanager with the label (DevTools Network or Tag Assistant). Expect that test to record one real conversion in Google Ads. (4) Optionally (Finch, small): log a one-line warning at start-up when the setting is non-empty but fails the regex, so a pasted "AW-.../label" no longer fails silently. Effort: about 15 minutes for the console and the setting; about 15 minutes for the optional log line. | Keep the plan, with these corrections.

1. Wren, in Google Ads > Goals > Conversions, checks three things:
   - Does a sign-up action exist for AW-1017057167? If so, what is its label (the part after the slash in send_to)?
   - Is it a PRIMARY action? A secondary action is ignored by bidding, so it would not fix optimisation even once it fires.
   - Is counting set to "One"? Re-renders are already de-duplicated by transaction_id, so "One" is the right choice.

2. Majid gives his go. Then the bare label is set on the production slot only, as a sticky setting: `az webapp config appsettings set --slot-settings @file`. Leave staging unset, because staging confirmations are not ad traffic.
   - No redeploy is needed, but an App Service settings write RESTARTS production. Device polls briefly get 503s and the Folderbird connector drops for about 30-60 s, so do it at a quiet hour.

3. How to verify. The send_to string is in the page source whenever the label is valid, accepted cookies or not. Seeing it there only proves the setting.
   - The proof that it fires is a request to googleadservices.com (or Tag Assistant) after accepting cookies, on a real confirmation of a throwaway account with a real mailbox.
   - An already-confirmed signed-in user (AccountController.cs:403-406) or a stale link (:414-418) gets no conversion, so test with a fresh account.

4. Expect undercounting even once the label is set. Consent Mode is BASIC (_GoogleTag.cshtml:18-21), so the conversion fires only with consent. The confirmation link arrives from email without a gclid. Attribution therefore needs the _gcl_aw cookie to have been set while the visitor was on the site from the ad, with consent given, in the same browser that opens the mail link.
   - Follow-up for Finch, a few hours: store the gclid/gbraid/wbraid at registration and upload confirmed sign-ups as offline conversions (or use enhanced conversions). That does not depend on the visitor's browser.

## 34. [tracking] No Meta pixel or Conversions API exists, so Meta cannot learn from any visit, download or sign-up
- Severity: high · kept 2/2 · owner: Majid (decision + privacy/banner wording), Wren (Events Manager + campaign objective), Finch (pixel code) · live site: yes · effort: Console objective change 10 minutes; pixel code 2-3 hours plus tests; Conversions API half a day
- Evidence: A repo-wide search for `fbq(`, `connect.facebook.net`, `facebook.com/tr`, `graph.facebook.com`, `_fbp`, `_fbc`, 'pixel id' and 'Conversions API' finds nothing in app code. The only 'fbclid' hits are report queries (.github/workflows/daily-report.yml:135,138; tools/telemetry/daily-visits.ps1:67,69). The click-id passthrough copies only Google ids: _GoogleTag.cshtml:71 `var AD = ['gclid', 'gbraid', 'wbraid'];`. The banner names only Google (_CookieConsent.cshtml:21-22 'Only if you accept do we load Google Analytics and Google Ads'), and so does the privacy policy (Privacy.cshtml:149-151 'Google Analytics and Google Ads are not loaded at all until you choose Accept'). The Facebook entries in Program.cs:215-224 are Facebook login (OAuth), not tracking.
- Impact: If the Meta campaigns optimise for leads, registrations or even landing-page views (the campaign objective is unknown from source), Meta has no events to optimise on. It falls back to people who click, often accidental taps inside the Facebook/Instagram app (3 of ~5 Meta visits came from there). Meta spend cannot be tied to any outcome, and fbclid is lost after the first page, so server logs cannot follow Meta visitors either.
- Fix: Short term (console): Wren sets Meta ad sets to a click/traffic objective that needs no pixel, and judges them from the server-side report rather than from Meta's conversion column. Proper fix, with Majid's go: Wren creates a pixel/dataset in Meta Events Manager. Finch loads it inside the same consent gate as Google (on Accept only, alongside fbLoadGtag), fires PageView on every page, Lead on CheckInbox (one-shot, same flag as the Google 'Sign-up submitted' conversion) and CompleteRegistration on ConfirmEmail, with eventID = user id so a later server-side Conversions API call deduplicates. Add 'fbclid' to the passthrough list at _GoogleTag.cshtml:71. Majid approves the banner and Privacy §6/§7 wording that names Meta. Optional later: a server-side Conversions API call from ConfirmEmail with a hashed email, which needs a Meta access token stored as a secret.
- Reviewer correction: 1. Wren, in the ad console, now (no site change, about 10 minutes): run the Meta ad sets on a Link clicks or Traffic objective, not Landing page views, Leads or Conversions, because those need a pixel. Judge the ads from the server-side report (fbclid arrivals in daily-report.yml D4/D5), not from Meta's conversion column.

2. Majid: decide whether to add Meta at all. He approves the banner and Privacy §6/§7 wording that names Meta. This must land in the same change as the pixel, never before or after.

3. Wren: create a Meta dataset (pixel) in Events Manager.

4. Finch, live site, about 3-4 hours including tests:
   - Add a `_MetaPixel.cshtml` partial included wherever `_GoogleTag` is (`_Layout` and `AlternateHome`). Load it only inside the Accept path: call it from `fbLoadGtag`, or add a parallel `fbLoadMeta` that the consent `decide()` also calls.
   - On Reject, stop it from `fbStopGtag`, and widen the cookie regex to cover `_fbp` and `_fbc`.
   - Take the pixel id from config and make it fail-safe while unset, the same pattern as `GoogleAds:ConfirmSignupLabel`.
   - Fire PageView on every page.
   - Fire CompleteRegistration on ConfirmEmail with eventID = the confirmed user id, mirroring the existing `transaction_id`. Queue it through the `fbAfterGtag` mechanism so an Accept on that page still sends it.
   - If a Lead event on CheckInbox is wanted, write it as new code with its own one-shot guard. There is no existing CheckInbox conversion to share a flag with, and CheckInbox is also reached by resends and refreshes.
   - Add 'fbclid' to the AD list at `_GoogleTag.cshtml:71` in the same change, so the pixel can read it on the page where the visitor accepts.

5. Optional, later: a server-side Conversions API call from ConfirmEmail with a hashed email. It needs a Meta access token stored as a secret and a legal/consent decision from Majid, since it would send data whatever the banner choice was. | Keep the plan, but correct five things.

1. **There is no Google "Sign-up submitted" conversion to share a flag with.** CheckInbox.cshtml at 5eb73c6 has no script and no gtag. The only Ads conversion is in Account/ConfirmEmail.cshtml:88-106: `send_to AW-1017057167/<GoogleAds:ConfirmSignupLabel>`, transaction_id = user id. CheckInbox is also reached from:
   - the resend path (AccountController.cs:394-396, sets ResendSentKey)
   - the expired-link paths (:442-454, set ConfirmExpiredKey)

   So the Meta Lead event needs its own guard. Fire it only on the redirect from a successful RegisterAsync: either a new one-shot TempData flag set beside `TempData[PendingEmailKey]` at :259, or at minimum `Email != null && !Sent && !Expired`. TempData is read once, so a refresh does not re-fire it.

2. **Gate the pixel exactly like gtag, and make Reject undo it.** Load it only from fbLoadGtag, or a sibling that the same Accept handler calls (_CookieConsent.cshtml:51), and queue events the same way fbAfterGtag does. Extend fbStopGtag (_GoogleTag.cshtml:51-62, which today expires only `_ga*` and `_gcl_*`) so it also revokes the pixel (`fbq('consent','revoke')`) and expires `_fbp` and `_fbc`. Expect Meta to see only visitors who accepted, as with GA4.

3. **CompleteRegistration on ConfirmEmail is right.** Use eventID = user id, because that page renders on every visit with a valid token.

4. **A server-side Conversions API call must respect the same consent.** Send it only when the visitor accepted, or have the privacy text say otherwise. §6 currently promises that nothing goes to an ad network on Reject (it names only Google, so Meta needs adding to §6 and the banner either way). The Meta access token goes in Key Vault, never in a setting value or a command line.

5. **Short-term console step.** A Traffic objective optimised for link clicks is likely what produces the in-app accidental taps, so "switch to a click/traffic objective" may already be the current state and not help. Wren should first read the actual objective and optimisation event in Ads Manager. Put utm_source=meta on every ad URL so the server report can tell Meta arrivals apart even when fbclid is dropped. Judge Meta from the server report until the pixel exists.

Ownership and effort as stated. It changes production; the pixel and the privacy/banner wording need Majid's go.

## 35. [tracking] Installer downloads and Register submissions are never tracked as events
- Severity: medium · kept 2/2 · owner: Finch (code), Wren (conversion action + GA4 key events) · live site: yes · effort: 1 hour code plus 15 minutes console
- Evidence: The repo's only gtag event is ConfirmEmail.cshtml:99 `gtag('event', 'conversion', ...)`. The Download page links to extensionless URLs, Views/Download/Index.cshtml:20-21 `const string winZip = "/download/windows"; const string winSetup = "/download/windows/setup";`, used at :159, :223, :232 and :247, with no click handler that reports anything (its script at :320-362 only switches the installer/ZIP choice). Register.cshtml:15 `Html.BeginForm("Register", "Account", FormMethod.Post, ...)` has no event either. Google's documented GA4 enhanced-measurement file_download only fires for links ending in a known file extension (.exe, .zip, ...), so these URLs would not be counted even with consent. Whether enhanced measurement is on in the GA4 property is unknown.
- Impact: The 3 Google-ad visitors who downloaded the installer are the warmest leads the campaign produced. Google learns nothing from them, so it cannot bid toward people like them while sign-ups are near zero.
- Fix: Finch adds one delegated click listener in _GoogleTag.cshtml (or the Download page) for `a[href^="/download/windows"]` and the Linux beta link. It sends `gtag('event','file_download',{file_name:'Folderbird-Setup', link_url:...})` when typeof gtag === 'function' and the Google Ads conversion for a new 'Installer download' action (label from a setting, fail-safe when unset, like ConfirmSignupLabel). It also sends a GA4 'sign_up_submit' event when the Register form submits. Wren creates the 'Installer download' conversion action and marks it SECONDARY (observe only) or, with Majid's go, primary until sign-ups have volume, then marks the GA4 events as key events.
- Reviewer correction: Keep the download half as proposed. Finch adds one delegated click listener (in _GoogleTag.cshtml or the Download page) for `a[href^="/download/windows"]` and `a[href^="/beta/"]`. That prefix still matches after the gclid script appends `?gclid=`, and after the toggle rewrites the hero href. The listener sends a GA4 `file_download` (file_name 'Folderbird-Setup' / 'Folderbird-Windows-zip' / 'Folderbird-Linux'), guarded by `typeof gtag === 'function'`. It also sends an Ads conversion `send_to: AW-1017057167/<label>`, with the label from a new setting such as `GoogleAds__InstallerDownloadLabel`. Like ConfirmSignupLabel, it emits nothing while unset and the label is shape-checked before it reaches the script. Since the page stays open while the file streams, gtag's default beacon transport delivers the event.

Change the sign-up half. Do not fire `sign_up_submit` on the form's submit event. A native submit listener also fires when jQuery unobtrusive validation blocks the submit, and when the server refuses the form (a refusal returns 200). Either case would count failures. Fire a `sign_up` event only after a confirmed account creation instead. Today that is the 302 to Account/CheckInbox. That page is also reached by resends and refreshes, so set a one-shot TempData flag in RegisterAsync on success and emit the event on CheckInbox only when the flag is present.

Wren creates the 'Installer download' action as SECONDARY (observe only). Making it PRIMARY changes what the paid campaign optimises for and how money is spent, so that needs Majid's own go. These events reach Google only for visitors who accepted cookies (basic consent mode, _GoogleTag.cshtml:18-21). Counts will stay partial, so judge the campaign against server logs, not GA4. The code change goes live on production via main → staging → swap. Effort is about 1-1.5 hours of code (plus the TempData flag) and 15 minutes in the console. | Finch (web, live site after the usual staging swap, about 1 to 1.5 hours):

(1) Downloads. Add one delegated click listener on the Download page for `a[href^="/download/windows"]`. Use a prefix match, because the gclid passthrough appends `?gclid=`. Add the same listener on Views/Beta/Linux.cshtml:66, the actual tarball link, not the /Download link to the /beta page. Each click sends GA4 `file_download` with `file_name` set to "Folderbird-Setup", "Folderbird-Windows-zip" or "Folderbird-linux". When a new `GoogleAds:InstallerDownloadLabel` setting is set, it also sends `gtag('event','conversion',{send_to:'AW-1017057167/'+label})`. The label is checked the same way as ConfirmSignupLabel, and nothing is sent while it is unset. Use the same `typeof gtag==='function'` guard and `window.fbAfterGtag` queue as ConfirmEmail.cshtml:98-105.

(2) Sign-ups. Do NOT fire on form submit. In RegisterAsync, set a one-shot TempData flag (for example "fb-reg-new") next to line 249. CheckInbox.cshtml sends the GA4 recommended `sign_up` event only when that flag is present, so resends, refreshes and expired-link redirects are not counted. Extend tests/consent_mode_tests.js so no event fires without consent.

Wren (console, 15 minutes):
- Create the 'Installer download' conversion action as SECONDARY and give Finch its label.
- Mark `sign_up` and `file_download` as GA4 key events.
- Making the installer conversion PRIMARY changes bidding and spend, so it waits for Majid's go.

State plainly in the report that all of these counts are lower bounds while the consent banner gates the tag. The server logs stay the reliable record of downloads.

## 36. [tracking] The ad click id is dropped at the Register POST and never stored on the server, so late consent cannot credit the ad and offline import is impossible
- Severity: medium · kept 1/2 · owner: Finch (code), Majid (consent/legal decision for storing click ids) · live site: yes · effort: Form carry 30-60 minutes; offline conversion import half a day to a day
- Evidence: The passthrough rewrites only <a> links (_GoogleTag.cshtml:76-85 `document.getElementsByTagName('a')`), not form actions. Register.cshtml:15 posts to /Account/Register with no query; AccountController.cs:249-250 then redirects to CheckInbox without it. A search of the .cs and .cshtml files for gclid/gbraid/wbraid/utm_/fbclid finds only _GoogleTag.cshtml:71, so no controller or table records the click id at registration.
- Impact: An undecided ad visitor who presses Accept only after submitting (on CheckInbox, or later on ConfirmEmail) gives gtag no click id to read, so the conversion cannot be credited to the ad. With no stored click id there is also no way to upload offline conversions later, for example confirmed sign-ups or the first PC registered, which is the real activation.
- Fix: Quick: carry gclid/gbraid/wbraid into the Register form, either through a hidden field or by appending them to the form action in the same carry() pass, and keep them through the 302 to CheckInbox via TempData. Then the click id is in the address wherever the visitor finally presses Accept. Larger, with Majid's legal go for visitors who did not consent: store the first-touch click id with the new user at registration and upload confirmations and first-device sign-ins as offline conversions through the Google Ads API.
- Reviewer correction: Step 0 (Majid, Google Ads console / App Service): check that GoogleAds__ConfirmSignupLabel is set on production. ConfirmEmail.cshtml:20-23 emits no conversion while it is unset, and then none of this matters.

Step 1, the quick fix (Finch; live site after the staging swap; about 1 hour including a case in tests/consent_mode_tests.js):
- In Register.cshtml, carry gclid, gbraid and wbraid from Request.Query into the form as hidden inputs. Shape-check each value against ^[A-Za-z0-9_-]{1,256}$ and drop anything else. Hidden inputs also survive the re-render that happens when the captcha or identity check fails.
- Add the three as optional properties on RegisterViewModel, or read them from Request.Form.
- On success, use `RedirectToAction(nameof(CheckInbox), new { gclid, gbraid, wbraid })` with only the values that passed the check. These are route values, so they end up in the query string. TempData is neither needed (the values are not secret) nor enough (it puts nothing in the address).
- What this achieves: a visitor who accepts on CheckInbox (or on a re-rendered Register page) lets gtag read the click id and write _gcl_aw. That credits the later ConfirmEmail conversion only when the confirmation link opens in the same browser.

What it does not cover: a visitor who accepts only on ConfirmEmail, and a confirmation link opened in a different browser or mail-app view, which is common on phones. Do not add the click id to the confirmation email link without Majid's decision: that would put an ad identifier into the user's inbox before consent.

Step 2, the real fix (Majid: legal/consent decision and a Google Ads API developer token; then Finch: about 1 day):
- Store the first-touch click id with the new user at registration.
- Upload confirmations, and the first PC registered, as offline conversions. Alternatively, use enhanced conversions for leads with a hashed email, which is also consent-gated. | If kept as a low-priority tracking item, Finch can do it in under an hour, and it changes the live site.

- In Register.cshtml, put gclid/gbraid/wbraid into hidden fields, or append them to the form action in the same carry() pass. Only do this when 'fb-consent' is unset.
- In RegisterAsync, re-append them on a refused re-render and to the CheckInbox redirect. Pass them as query values; TempData would not put them in the address that gtag reads.

Say plainly that this only rescues visitors who accept on CheckInbox or on a re-rendered Register page, and never one who accepts on ConfirmEmail.

First, check that GoogleAds__ConfirmSignupLabel is set on the production slot. This is Majid's or Wren's job, done in the console or App Service settings.

The cross-browser loss (the email opened elsewhere) is only fixed by keeping the click id on the server and uploading conversions offline or as enhanced conversions. That is limited to consenting visitors unless Majid decides otherwise on legal advice, and takes about half a day to a day.

## 37. [tracking] The daily report counts ad-tagged requests, not ad arrivals, and how many it sees depends on each visitor's banner choice
- Severity: medium · kept 2/2 · owner: Finch · live site: no · effort: 30-60 minutes
- Evidence: .github/workflows/daily-report.yml:135 (D4) and :138 (D5) count `sum(ItemCount)` of AppRequests where `Url has 'gclid' or Url has 'utm_' or Url has 'fbclid'` and label them 'arrivals' / 'ad clicks'; tools/telemetry/daily-visits.ps1:67,69 are the same. Since d3723bc (2026-11-08), _GoogleTag.cshtml:70 `else if (c !== 'denied')` copies gclid into every internal link, but only for visitors who have not chosen yet. After Accept or Reject the id stops travelling, and fbclid is never copied.
- Impact: '77 ad-tagged page loads' against 37 Google Ads clicks is consistent with undecided visitors producing one tagged request per page they open. Meanwhile visitors who chose drop out of the downstream counts, such as 'ad visitors who downloaded'. The team's own numbers can overstate arrivals and understate ad-driven downloads or registrations, at exactly the moment they are used to judge the ads.
- Fix: In D4/D5 and the funnel query, count distinct click ids: `extend g = extract('[?&](gclid|gbraid|wbraid|fbclid)=([^&]+)', 2, Url) | summarize arrivals=dcount(g)`. Count arrivals only on the first request per id (for example where the path is '/' or the request has no internal referrer). Label downstream ad-attributed counts 'visitors who had not answered the banner'. CI/report only.
- Reviewer correction: This is CI/report-only (daily-report.yml D4/D5 and the generated twin daily-visits.ps1, plus campaign-health.yml:177). Nothing on the live site changes.

1. Count clicks from the unsampled front-end log, which the report already queries (D10b uses it):

```
AppServiceHTTPLogs | where TimeGenerated > ago(24h) | where tolower(_ResourceId) !has '/slots/staging' | extend g = extract('(?:^|&)(gclid|gbraid|wbraid|fbclid)=([^&]+)', 2, CsUriQuery), src = extract('(?:^|&)(gclid|gbraid|wbraid|fbclid)=', 1, CsUriQuery) | where isnotempty(g) | summarize first=min(TimeGenerated), hits=count() by src, g | summarize clicks=count_distinct(g), tagged_requests=sum(hits) by src
```

Do not use `first` as a column name: it is reserved and breaks KQL. Rename it, for example to `t0`.

2. Optionally, define an arrival as a tagged request whose `Referer` does not contain folderbird.com.

3. Report utm_-only rows on their own line as "utm-tagged requests". They carry no click id.

4. Change the headline label from "ad clicks" to "ad click ids (distinct)". Show `tagged_requests` beside it, so the gap is visible.

5. For any ad-attributed downstream count, such as installer downloads by visitors carrying a gclid, add a note in the report that it only covers visitors who had not answered the cookie banner yet.

6. Fix campaign-health.yml:177 the same way. Replace the line count with a count of distinct ids, for example with `grep -oE` and `sort -u`.

Owner: Finch. Effort: about 30-60 minutes, plus one dispatch of the report to check the output. | Rewrite D4 and D5 in .github/workflows/daily-report.yml to count distinct click ids from the unsampled front-end log, then regenerate the twin block in tools/telemetry/daily-visits.ps1. The repo rule is that the two must never drift.

The D4 query:
```
AppServiceHTTPLogs | where TimeGenerated > ago(24h) | where tolower(_ResourceId) !has '/slots/staging' | where CsMethod == 'GET' | extend q = strcat('?', CsUriQuery) | extend cid = extract('[?&](gclid|gbraid|wbraid|fbclid)=([^&]+)', 2, q), src = extract('[?&](gclid|gbraid|wbraid|fbclid)=', 1, q), utm = extract('[?&]utm_source=([^&]+)', 1, q) | where isnotempty(cid) or isnotempty(utm) | summarize ad_clicks=dcountif(cid, isnotempty(cid)), utm_only_requests=countif(isempty(cid)), tagged_requests=count() by src, hour=bin(TimeGenerated,1h)
```
D5 is the same query grouped by country, if the HTTP log carries one; otherwise keep the AppRequests version and rename its column `tagged_requests`.

Then:
- Retitle both sections "distinct ad click ids (Google gclid/gbraid/wbraid, Meta fbclid)" and keep tagged_requests next to them, so the gap stays visible.
- Note in the report header that any ad-attributed downstream count (for example installer fetches whose URL has gclid) covers only visitors who had not yet answered the cookie banner. It is a lower bound.

This is CI and report only, with no production change. Owner: Finch. Effort: 30-60 minutes, including checking the HTTP log column names (CsUriQuery, CsMethod) against the real workspace before merging.

## 38. [tracking] (Cross-stage, verified) The Windows app opens straight into a sign-in form that offers no way to create an account
- Severity: high · kept 2/2 · owner: Finch (web prompt), Swift (app link; release needs Majid's signing) · live site: yes · effort: Web 1 hour; app 1-2 hours plus a signed release
- Evidence: tools/windows-installer/Folderbird.iss:136 only offers 'Start Folderbird now' and opens no web page. The app's sign-in window (folderbird-agent 1f14100, FileRouteClient/LoginForm.Designer.cs) has six labels, two text boxes, two checkboxes and one 'Sign In' button: no link, no 'Create account'. Its subtitle is 'Connect this device to your account' (:77). A non-existent account gets 'Incorrect email or password. Please try again.' (LoginForm.cs:145). The only registration prompt is on the web Download page, below the hero button (Views/Download/Index.cshtml:185 'No account yet? <a href="/Account/Register">Create one free</a>').
- Impact: The 3 ad visitors who downloaded the installer but never signed up match this dead end: install, a sign-in box, no account, no route to one. It is also unmeasured. Neither Google nor the server report connects an installer download to a later registration.
- Fix: Web, fast: on the Download page, when the visitor is not signed in, show a 'Create your free account while it downloads' prompt (link to /Account/Register) the moment they click any Windows download button. App: add a 'No account? Create one free' link to LoginForm that opens https://folderbird.com/Account/Register?src=app, and change the wrong-password message to mention it. This ships in the next signed Windows release.
- Reviewer correction: The fix is right in direction. These details make it safe.

**Web (Finch, about 1 hour, reaches production only after the usual swap):**
- Show the account prompt only when the visitor is not signed in. Check `User.Identity.IsAuthenticated` in Views/Download/Index.cshtml.
- Do not call `preventDefault` on the download links, or downloads will break. Leave the existing hero/segmented-control script (:323-361) unchanged; it rewrites `#fbHeroWin`'s href.
- `_Layout` renders `@section scripts` above the page body. Any new click handler must wait for DOMContentLoaded, like the existing `init`.
- The lowest-risk version is static: put "No account yet? Create one free" right under the hero download row. A click-triggered prompt can come after that.

**App (Swift, about 1-2 hours plus a release):**
- Add a LinkLabel "No account? Create one free" to LoginForm that opens `https://folderbird.com/Account/Register?src=app` with `Process.Start`. On .NET Framework this uses the shell by default.
- Add the same hint to the "LoginFailed" message at :145.
- This reaches devices only through a new signed release: `publish-release.ps1` with Majid's password and OTPs, then move the seven DownloadController constants and the `AgentUpdate__*` settings together. Number it above 1.2.8.1, and check that AssemblyVersion matches AssemblyFileVersion.

**Optional, installer only:**
- Add a second, unchecked postinstall [Run] entry: "Create a free account (opens folderbird.com)", using `shellexec` with `/Account/Register?src=installer`.
- Auto-updates ship the zip, not the installer, so this reaches only new installs, which is exactly this audience.
- It still needs a newly signed Setup exe and new SetupBlob/SetupSha256/SetupBytes constants.

**Measuring it:** the `src` query string shows up in the HTTP logs, so app-originated sign-up attempts can be counted. | 1) Web, live site, Finch, about 1 hour. On /Download, when the visitor is not signed in (User.Identity.IsAuthenticated in the view), clicking either Windows download button shows an inline panel. Do not call preventDefault, so the file download still starts. The panel reads: "While it downloads: create your free account (you'll confirm your email, then sign in on the PC)", with a link to /Account/Register?src=download. Also change the hero line from "sign in once" to "sign in once with a free account" and link it. Measure clicks with a src parameter on Register.

2) Installer, Swift plus Majid's signing, about 30 minutes plus a signed rebuild. No new app version is needed because the installer is built from the published zip. Add an Inno [Run] entry: `Filename: "https://folderbird.com/Account/Register?src=installer"; Description: "Create a free Folderbird account"; Flags: shellexec postinstall nowait skipifsilent unchecked`. Re-sign it and move the three Setup* constants.

3) App, Swift, 1-2 hours plus the next signed release (1.2.8.2 or later). Add a "No account? Create one free" LinkLabel that opens https://folderbird.com/Account/Register?src=app with UseShellExecute=true. On LoginFailed, show: "Incorrect email or password. No account yet? Create one free at folderbird.com, confirm your email, then sign in here." This only helps people who install after that release ships.

## 39. [tracking] Completed subscriptions are not reported to Google or Meta
- Severity: low · kept 2/2 · owner: Finch (code), Wren (conversion action) · live site: yes · effort: 1-2 hours
- Evidence: Views/Home/Pricing.cshtml:225-229 `Paddle.Checkout.open({ ... settings: { displayMode: 'overlay', successUrl: window.location.origin + '/Pricing?welcome=1' } })`. Nothing reads 'welcome' (no hits in Pricing.cshtml or HomeController.cs), and there is no eventCallback/checkout.completed handler, so no purchase event or conversion exists.
- Impact: When paid plans start selling, the ads will not learn which clicks bring paying customers, and spend cannot be compared against revenue. This matters little while sign-ups are zero.
- Fix: On checkout.completed (Paddle eventCallback), or on /Pricing?welcome=1, fire a consent-guarded Google Ads 'Purchase' conversion and a GA4 'purchase' event with value, currency and transaction_id = the Paddle transaction id. Add the Meta 'Purchase' event too once a pixel exists. Wren creates the Purchase conversion action.
- Reviewer correction: 1. Where the callback goes. In Paddle.js v2, eventCallback is a property of `Paddle.Initialize({ token, eventCallback })`, not of `Checkout.open`.

2. The redirect race. `successUrl` makes Paddle navigate away when checkout completes. A gtag beacon fired inside the callback can be lost in that navigation. So split the work:
   - In the callback, on `ev.name === 'checkout.completed'`, save `{id: ev.data.transaction_id, value: ev.data.totals.total, currency: ev.data.currency_code}` to sessionStorage, wrapped in try/catch. I have not checked whether totals.total is in major or minor currency units; check that on a sandbox checkout before shipping.
   - On /Pricing?welcome=1, read that entry once, fire the conversion, then delete it.

3. Follow the ConfirmEmail.cshtml pattern exactly:
   - A config-gated label, `GoogleAds:PurchaseLabel` (App Service `GoogleAds__PurchaseLabel`), which emits nothing while unset.
   - Run the conversion directly if `typeof gtag === 'function'`, else queue it on `window.fbAfterGtag`. That way it stays consent-gated, and it fires only if the visitor consents on that page.
   - Send `gtag('event','conversion',{send_to:'AW-1017057167/'+label, value, currency, transaction_id: id})` plus a GA4 `gtag('event','purchase',{transaction_id:id, value, currency})`.
   - Use transaction_id so a refresh or a second visit does not double-count.

4. Meta. A Meta Purchase event only once a pixel exists. None exists today.

5. A sturdier option for later. Record the purchase on the server from the Paddle webhook in PaddleController as an offline or enhanced conversion. That needs the gclid stored at sign-up, so it is hours of work, not minutes.

6. Ownership and rollout. Wren creates the Purchase conversion action and passes its label to Majid or Finch to set. Finch writes the code. Shipping is a live-site change: a push to main reaches staging, then needs a swap.

Effort: about 1-2 hours plus one sandbox checkout to confirm the event fields. | 1. Add a config-gated label `GoogleAds:PurchaseLabel` (App Service `GoogleAds__PurchaseLabel`). Shape-check it like ConfirmSignupLabel, and emit nothing while it is unset.
2. Pass `eventCallback` to `Paddle.Initialize` (or `Paddle.Update`). On `checkout.completed`, save the event's transaction id, total and currency in sessionStorage.
3. On `/Pricing?welcome=1`, read that entry once and clear it. Fire `gtag('event','conversion',{send_to:'AW-1017057167/'+label, value, currency, transaction_id})` and a GA4 `purchase` with the same values, through the existing `typeof gtag` / `window.fbAfterGtag` pattern from ConfirmEmail.cshtml:96-105, so it only runs after consent. A reload then cannot double-count, and the transaction id lets Google deduplicate. Check the exact field names and value units against Paddle.js v2's checkout.completed payload before coding; I did not verify them here.
4. Add Meta Purchase only once a pixel exists (none today).
5. Expect undercounting under the basic consent mode. Exact revenue attribution would need a server-side upload from the Paddle webhook (PaddleController) with a captured gclid, which is a larger, separate job.
6. While in this code: `welcome=1` currently shows the plain pricing page again. If the webhook has not set PaddleSubscriptionId yet, `P.managed` is false and the buy buttons are live, which invites a second, parallel subscription. Show a thank-you banner on welcome=1 and disable the buttons there. This is unverified at runtime because webhook timing is unknown.

Owners: Finch writes the code; Wren creates the Purchase conversion action and gives Finch the label. It changes the LIVE site (Pricing page script) once swapped. Effort: about 1-2 hours.

## 40. [subscription] The only thing a paid plan buys is a 3rd PC; most buyers never need one, and two listed paid perks do not exist
- Severity: high · kept 2/2 · owner: Majid (pricing model + legal wording); Finch (copy change + any new gate) · live site: yes · effort: Copy fix: 15 minutes. A new feature gate: hours to a day, plus a Majid decision
- Evidence: Sparrow (free) already includes everything: Pricing.cshtml:69-73 '2 devices · Browse & download from any browser · Cross-device search · AI / agent connector (MCP + REST)'. The only enforced entitlement in the codebase is the device count: AuthController.cs:1579-1596 (select coalesce("DeviceLimit",2) … if (current >= limit) return false). A grep for Tier/falcon/eagle finds Tier read only for display (ManageController.cs:63) and set by the webhook. No feature is gated on it. The paid cards still promise 'Priority transfers' (Pricing.cshtml:90), 'Higher transfer allowance' and 'Priority support' (107-108), and Phoenix promises 'SSO, audit & onboarding' (124). Nothing in the code implements priority or an allowance per tier, and there is no SSO.
- Impact: Most home users have 1 or 2 PCs, so they get the whole product free and never hit a reason to pay. The only upgrade trigger is signing in a third computer. Separately, selling 'priority transfers' and a 'higher transfer allowance' that do not exist risks refund disputes and a Paddle policy review of the pricing page.
- Fix: Majid decides the model. For example: free = 1 PC (or 2) with browse/download only; paid = AI connector/MCP + REST exec, upload, sharing, more devices. Or keep 2 free and add a usage limit that the code actually enforces. Until that is decided, Finch removes or rewrites the three unimplemented bullets so the page sells only what exists (for example 'Up to 6 computers', 'Email support').
- Reviewer correction: Copy fix (Finch, about 15 minutes, live site after a swap; Majid approves the wording):
- Remove or replace only the two transfer bullets. "Priority transfers" (Pricing.cshtml:90) and "Higher transfer allowance" (:107) have no code behind them on any tier.
- Keep "Email support" and "Priority support" only if Majid confirms he will honour them. Better, give a concrete response time, for example "Email support, reply within 1 business day".
- On Phoenix (:124), keep "audit", which exists. Change "SSO" to "SSO on request", or drop it. The app has only consumer Google/Microsoft logins that switch on by config, no SAML or enterprise OIDC.
- Also correct the false comment at LicenseService.cs:184 ("tiers gate features there").

Pricing model (Majid decides first): if the model changes to gate features, line 53's "Every plan includes … the AI / agent connector — you only pay as you add more computers" must be rewritten in the same change. Two risks to plan for:
1. Gating MCP/REST behind a paid tier would break existing free users' connectors.
2. It would also break the reviewer path for the Claude connector and ChatGPT plugin submissions, which use the tester@folderbird.com account. Upgrade that account first, and plan what happens to existing free users' connectors rather than cutting them off silently.

Lowering the free device count is lower risk. The limit check only blocks new devices (AuthController.cs:1574-1596), so existing devices keep working. Even so, any downgrade needs Majid's go, and someone must check the existing "Locked" downgrade handling. | Now (Finch, a copy change only; it reaches production through the usual main → staging → swap):
- Pricing.cshtml:90 and :107: remove "Priority transfers" and "Higher transfer allowance", or replace them with true lines such as "Up to 6 / 20 computers".
- Pricing.cshtml:91 and :108 ("Email support", "Priority support"): keep them only if Majid commits to a response time; otherwise drop them.
- Pricing.cshtml:124: change "SSO, audit & onboarding" to "Audit trail and onboarding; single sign-on scoped during onboarding", or drop "SSO".
- LicenseService.cs:184: correct the false comment "tiers gate features there".
- Effort: about 15-30 minutes plus the swap.

Later (Majid decides the pricing model): any new gate must:
- leave the Android app's key scopes working (browse, download, upload, devices:enroll, exec), or that app breaks for free users;
- keep the directory reviewer account working;
- grandfather existing free accounts that already have 2 devices;
- come with matching updates to Pricing.cshtml:53, the Terms, the Play listing and the Claude/ChatGPT submission packs, which describe the connector as free.

Effort for a gate: about a day of code, plus review and staging tests.

## 41. [subscription] Live checkout was never verified, and a webhook error is acknowledged with 200, so a paying customer can stay on the free plan with no retry and no alert
- Severity: high · kept 2/2 · owner: Finch (code + alert); Majid (real-card test, Paddle console check of the notification destination and subscribed subscription.* events) · live site: yes · effort: Code: about 1 hour. Alert: 15 minutes. Test purchase: 20 minutes
- Evidence: PaddleController.cs:102 has the comment 'record only after successful handling (so a transient failure can be re-delivered)', but the catch at 105-109 does `return Ok(); // 200 so Paddle doesn't hammer retries`. Paddle therefore never re-delivers after a database error in UpdateUserEntitlement (125-165). When the user cannot be resolved (resolvedUid null, line 97/143), the event is still marked processed (102) and answered 200. The only trace is a Console.WriteLine. Nothing checks that Paddle__WebhookSecret is set: the Pricing diagnostics (Pricing.cshtml:168-176) check only the token, the prices and the environment. If the secret is missing, every webhook is answered 403 (lines 47-51). The project notes say a live card purchase has never gone through end to end.
- Impact: The first paying customer could pay $9 and still be stopped at 2 devices, and nobody would know until they complain. That is a refund at best and a chargeback at worst. Today it is impossible to tell whether the whole path (domain approval, notification destination URL, subscribed events, secret) works.
- Fix: (1) Finch: return 500 from the catch for a database or transient exception, so Paddle retries with backoff. Keep 200 only for a body that does not parse. On subscription.activated/updated with resolvedUid == null, log at error level and do not MarkProcessed. Add an Azure log alert on '[PADDLE] webhook processing error' and 'signature REJECTED'. (2) Majid: make one real Falcon monthly purchase with a throwaway account (NOT Majid's own account, see the separate finding). Confirm that Manage shows 'Falcon · 6 devices' within a minute, then cancel and refund in Paddle and confirm it drops back to Sparrow.
- Reviewer correction: **Finch (code; goes main -> staging -> swap, so it changes production):**
1. In the catch, return `StatusCode(500)` so Paddle retries. Keep the reply short; idempotency through PaddleEvents already makes retries safe. Paddle times a delivery out at about 5 s, so a slow handler is retried too, and that is fine.
2. For grant events (subscription.activated, updated, resumed) where the user cannot be found, log at error level, do not MarkProcessed, and return 500. Paddle's bounded retries then cover the case where `activated` arrives before `created` has bound the subscription id. Also treat an UPDATE that changed 0 rows as "user not found", using the ExecuteNonQuery count instead of ignoring it.
3. Add a Log Analytics scheduled-query alert to folderbird-oncall:
   - Any `[PADDLE] webhook processing error`.
   - Any grant event logged with no user.
   - `signature REJECTED` at or above 3 per hour. The endpoint is anonymous, so a single hit can be a scanner.

Effort: about 1 hour of code plus 15-20 minutes for the alert.

**Majid (console and billing, production):**
1. Before any purchase, open Paddle > Developer tools > Notifications. Confirm the destination URL is `https://folderbird.com/api/paddle/webhook`, the subscription.* events are subscribed, and the delivery log shows 2xx responses. Paddle's notification simulator can send a signed test event; the app log should show `[PADDLE] subscription.* ...`, not `REJECTED`. That proves the secret and reachability without a card. Simulator data has no matching user, so no tier will change.
2. Then make one real Falcon monthly purchase with a throwaway account. Manage should show "Falcon" and "x of 6 devices used".
3. In the Paddle dashboard, cancel IMMEDIATELY rather than at period end. `subscription.canceled` only fires when the cancel takes effect. Confirm the plan drops to Sparrow, then refund.

About 30 minutes for both. | Keep the direction, but turning on retries without these guards is risky.

(1) Finch, retries. Sort the exceptions.
- Return 200 for a body that cannot be processed: JsonException, or the InvalidOperationException that TryGetProperty throws when the root is not an object.
- Return 500 for NpgsqlException, TimeoutException and SocketException. Paddle then retries with backoff.

(2) Finch, ordering guard. Add it before enabling retries. A retried older event, such as a `subscription.updated` with status=active, can arrive after a newer `subscription.canceled` and grant the tier again. Today that cannot happen only because nothing is ever retried. Fix:
- Store the top-level `occurred_at` per subscription, for example a `PaddleEventAt` column on AspNetUsers.
- Skip, but still MarkProcessed, any event older than the stored value.

(3) Finch, unresolved user.
- In UpdateUserEntitlement, check the row count from ExecuteNonQuery and return null when it is 0.
- For a subscription.* grant event with resolvedUid == null, log `[PADDLE] UNRESOLVED`, do not MarkProcessed, and return 500. This also covers `activated` arriving before `created` has stored the subscription id. Only skipping MarkProcessed while still answering 200 does not trigger a retry; it only lets a manual replay from the Paddle dashboard go through.

(4) Finch, alert. Add an Azure log alert on AppServiceConsoleLogs for `[PADDLE] webhook processing error`, `[PADDLE] UNRESOLVED` and `signature REJECTED`.

(5) Majid, real-card test. This must run on production, because the Paddle settings exist only on the production slot.
- Use a throwaway account. Buy Falcon monthly.
- Confirm Manage shows Falcon and "x of 6 devices used".
- In Paddle, cancel the subscription with "immediately", not "end of billing period", which keeps it active until the period ends. Then refund.
- Confirm the account drops back to Sparrow and any extra devices lock.
- Check the Paddle notification log shows 200 for created, activated and canceled.

Live site impact: the code reaches production only after a deliberate swap. The test purchase is production-only.

Effort: about 2 hours of code including the ordering guard, 15 minutes for the alert, 20 minutes for the test.

## 42. [subscription] A signed-out 'Choose Falcon' goes to Login, not Register, and the chosen plan is lost through sign-up
- Severity: medium · kept 2/2 · owner: Finch · live site: yes · effort: 2-3 hours
- Evidence: Pricing.cshtml:214: `if (!P.auth) { window.location = '/Account/Login?returnUrl=%2FPricing'; return; }`. The Login page's Register link drops the return URL: Login.cshtml:66 `@Html.ActionLink("Register", "Register", "Account", new { }, …)`. Register() takes no returnUrl (AccountController.cs:147-150). After confirmation the page sends the user to the devices list: ConfirmEmail.cshtml:30 `var continueUrl = Url.Action("Index", "Device");` and line 65 'Go to my devices'.
- Impact: Ad visitors have no account. A visitor ready to pay is shown a password box for an account they do not have. If they find Register, after confirming the email they land on an empty devices page with no memory of the plan. They must find Pricing again and click again, and the yearly toggle resets to monthly.
- Fix: In fbSubscribe, send signed-out users to /Account/Register?plan=falcon&period=y|m (and keep 'Already have an account? Sign in' carrying the same returnUrl). Carry returnUrl/plan through Register → CheckInbox → ConfirmEmail (for example in the fb.reg cookie payload or TempData). Point ConfirmEmail's continue button at /Pricing?plan=falcon&period=…, which opens checkout automatically. Also make Login.cshtml:66 pass ReturnUrl to Register.
- Reviewer correction: Finch, web code. The fix changes production once it is deployed. About 2-3 hours.
1. Pricing.cshtml:214. When signed out, go to `/Account/Register?returnUrl=` + encodeURIComponent('/Pricing?plan=' + tier + '&period=' + period).
2. Register GET takes `returnUrl` and hands it to its "Sign in" link (Register.cshtml:63). Login.cshtml:66 passes `ViewBag.ReturnUrl` to its Register link.
3. On the Register POST, store returnUrl only if `Url.IsLocalUrl(returnUrl)` is true. Put it in a separate short-lived, HttpOnly, Path=/Account cookie, for example `fb.ret`. Do not change the payload format of fb.reg. fb.reg currently unprotects to a bare user id, and changing that format would break confirmation links already sent with the old format. Also pass returnUrl to CheckInbox's Sign-in link (CheckInbox.cshtml:54).
4. In ConfirmEmail, set continueUrl to the stored local returnUrl, falling back to Device/Index. Use it for "Go to my devices", "Not now" and the `enable2faUrl` returnUrl. Also add `?returnUrl=` to the "Sign in" fallback at line 81. That covers people who confirm the email on a different device, where the cookie is absent, so give that link a server-side default of /Pricing whenever the confirm link itself carries the plan.
5. On Pricing, read `plan` and `period`. Only accept falcon or eagle, and m or y. Set `#billToggle` and `period`, then scroll to and highlight the chosen card. Do not auto-open Paddle on page load: the page script only runs Paddle.Initialize if the script has loaded, `P.managed` users must go to the portal, and an unprompted checkout overlay is surprising. If auto-open is still wanted, open it only when `P.auth && !P.managed && window.Paddle` is true, after init, and only once (strip the parameters with `history.replaceState`). | Pricing.cshtml fbSubscribe: when signed out, send the visitor to '/Account/Register?returnUrl=' + encodeURIComponent('/Pricing?plan=' + tier + '&period=' + period). On load, read plan/period from the query string. If period=y, set #billToggle checked and dispatch 'change' so the displayed prices match. Highlight the chosen card and show a "Continue to checkout" button that calls fbSubscribe(plan); do not open Paddle automatically. AccountController: Register(string returnUrl = null) puts returnUrl in ViewData; the Register form posts it back. On success, RegisterAsync, if Url.IsLocalUrl(returnUrl), writes it to a SEPARATE cookie (for example fb.next: HttpOnly, Lax, Path=/Account, 24h). Leave fb.reg's payload as the bare user id, because ConfirmEmail compares Unprotect(reg)==user.Id and old cookies must keep working. ConfirmEmailAsync reads fb.next, checks it again with Url.IsLocalUrl, deletes it, and passes it to the view. ConfirmEmail.cshtml sets continueUrl from that value, falling back to Device/Index. In the 'confirmed' (other browser) state, link to Login?ReturnUrl=<same>. Login.cshtml:66 passes new { ReturnUrl = ViewData["ReturnUrl"] } to Register, and Register's "Already have an account? Sign in" link passes it back. The change ships to staging on push and reaches production only through a deliberate swap.

## 43. [subscription] At the device limit, no path leads to checkout: the web shows '2 of 2 slots used' with no upgrade link, and 'Add a device' does not warn
- Severity: medium · kept 2/2 · owner: Finch · live site: yes · effort: 1-2 hours
- Evidence: DeviceList.cshtml:157 `@if (_limit > 0) { <span> &middot; @_used of @_limit slots used</span> }` has no link or button. The upgrade link exists only in the locked-devices banner, rendered when `ViewBag.HasLocked == true` (171-176), which a free user at 2/2 never sees. fbAddDevice (496-501) calls /Device/GenerateDeviceCode and prompts 'Install the Folderbird app on that PC and sign in' without comparing _used to _limit. The user discovers the limit only after installing on the third PC. The ToggleDeviceLock and locked-device messages (DeviceController.cs:498, 1368) say 'upgrade' as plain text with no link.
- Impact: The one moment a free user is ready to pay (wanting a third PC) is the moment the web gives them no button. Instead they install the app on a PC that will then be refused.
- Fix: When _used >= _limit on a non-paid tier: show 'You're using 2 of 2 free devices — Falcon gives you 6 for $9/month' with an 'Upgrade' button to /Pricing?plan=falcon (one click to the Paddle overlay). In fbAddDevice, when full, show that same choice before generating a code. Turn the two TempData messages into links.
- Reviewer correction: Owner: Finch. Effort about 1-2 hours. Ship to staging, then production on a swap.

1. In DeviceList.cshtml, after the `_used`/`_limit` block (around line 157), add a line when `_limit > 0 && _used >= _limit`: "All N device slots are in use. To add another computer, upgrade your plan or lock or remove one you no longer use." Add an "Upgrade" button that links to /Pricing. Show it on every tier below the top one, not only free.

2. In fbAddDevice (lines 496-502), when the page is full (pass `_used` and `_limit` into the script), first show a confirm dialog: "This account is at its device limit (N of N). A new PC will be refused at sign-in. OK = see plans, Cancel = get the code anyway." Only warn, never block. A PC that is already registered is matched by its MAC address and takes no new slot, and a user can still free a slot by locking a device. So the code must stay available.

3. Do not link to /Pricing?plan=falcon unless Pricing.cshtml is also changed to read that parameter, for example to scroll to and highlight that plan. The overlay should still open only from the user's click on "Choose Falcon": a script-opened overlay can run before Paddle has loaded, and it also skips the sign-in and existing-subscriber checks inside fbSubscribe. Do not copy "$9" or "6 devices" into a second place. Use generic wording, or read the limits from one shared source.

4. The two TempData messages (DeviceController.cs:498 and 1368) are HTML-encoded by Razor at DeviceList.cshtml:169. Do not put an `<a>` tag inside TempData, because that would need Html.Raw. Instead set a separate flag, for example `TempData["DeviceMsgUpgrade"] = true`, and have the view render an encoded "Upgrade your plan" link next to the message.

5. Optional, Windows app (Swift): the DeviceLimitReached text in LoginForm.cs:167 could open https://folderbird.com/Pricing in the browser instead of showing plain text. This needs a signed app release, so do it after the web change. | Owner: Finch for the website, Swift for the optional app change. Effort: about 1-2 hours. These are website changes, so they reach the live site (staging first, then a swap).

1. **Slot bar.** In DeviceList.cshtml, when `_used >= _limit` and the user is on the free plan (`_limit == 2`, or the tier is sparrow), add a link or button under the slot bar. Suggested copy: "You're using 2 of 2 free devices. Falcon gives you 6 for $9/month — Upgrade". For a paid user at the cap, point to the next plan instead (Falcon 6/6 → Eagle).

2. **Pricing link.** Link to `/Pricing`, or add a small handler on Pricing.cshtml that reads `?plan=falcon`. The handler should call `fbSubscribe(plan)` on load only if:
   - the visitor is signed in,
   - they have no subscription,
   - the plan is falcon or eagle.

   Without that handler, `?plan=falcon` does nothing. A signed-out visitor already goes to the login page with returnUrl=/Pricing, so keep that path.

3. **Add a device.** In fbAddDevice, check before asking for a code. If the account is full, show the same upgrade choice first, with a "Continue anyway" option, because the user may plan to remove a device. Do not block the code.
   - Most people never press this button. It is only needed for 2FA accounts; others just install the app. So item 1 is the part that matters.

4. **The two "upgrade" messages.** These are the TempData messages at DeviceController.cs:498 and :1368. They are encoded through `@ViewBag.DeviceMsg`, so adding an `<a>` to the message string will not work. Either:
   - add an "upgrade" flag in TempData and render the link in the view, or
   - always render a Pricing link beside the DeviceMsg box.

5. **Optional, Swift.** Make the app's DeviceLimitReached message (LoginForm.cs:166) a clickable link that opens https://folderbird.com/Pricing.

## 44. [subscription] The Windows app's device-limit message is a plain label: no link, no plan name, no button
- Severity: medium · kept 2/2 · owner: Swift · live site: yes · effort: 1 hour of code, plus a signed Windows release (owner OTPs)
- Evidence: folderbird-agent FileRouteClient/LoginForm.cs:163-169: `case "DeviceLimitReached": ShowMessage("You've reached your plan's device limit. Remove a device you no longer use, or upgrade your plan at folderbird.com/Pricing.", ErrorColor);`. ShowMessage (LoginForm.cs:76-80) only sets lblMessage.Text. The form has no LinkLabel (LoginForm.Designer.cs:33-48) and the app has no other Pricing or upgrade entry point (grep finds only this line).
- Impact: This is the single point where the product tells a free user to pay, and it asks them to retype a URL by hand from a red label.
- Fix: Add a LinkLabel or 'See plans' button under the message that opens https://folderbird.com/Pricing?plan=falcon&from=app (Process.Start with UseShellExecute), and a second 'Manage my devices' link to /Device. Ship it in the next signed release.
- Reviewer correction: Swift, Windows app: put a LinkLabel (or a "See plans" button) under lblMessage, shown only in the DeviceLimitReached case and hidden again at the start of DoLoginAsync. Open the link with Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }) inside a try/catch, like the existing ms-settings launch in MyCustomApplicationContext.cs:610. Add a second "Manage my devices" link to /Device, because the trash button that frees a slot lives there.

- **Build the URL from the configured base host, not a hard-coded https://folderbird.com.** A test-profile copy with FOLDERBIRD_BASEURL set must open staging, not production.
- **Drop the ?plan=falcon part.** Views/Home/Pricing.cshtml never reads a plan query, so it would not preselect anything. Preselecting would be a separate change for Finch. A ?from=app tag is harmless and lets the logs count these clicks.
- **The link works for a signed-out browser.** The default browser may not be signed in, but fbSubscribe already sends a signed-out visitor to /Account/Login?returnUrl=%2FPricing, which returns them to Pricing after sign-in. No web change is needed.
- **Naming the plan or the limit ("2 of 2 on Sparrow") needs Finch.** The server's reply would first have to carry the limit and count, while staying exactly "DeviceLimitReached" for apps already installed. Keep the app's text generic until then.

Effort: about 1 hour of code. It reaches users (production) only through the next EV-signed Windows release, which needs Majid's OTPs and the usual arming of the update channel. | Owner: Swift (Windows app). Effort: about 1-2 hours of code, plus a signed release that the owner must run (password and OTPs).

1. In the DeviceLimitReached case, keep the generic wording but name where to act, for example: "This account is at its plan's device limit. Remove a PC you no longer use, or see plans." Do not show a plan name or number; the app does not receive them.
2. Add two LinkLabels under the message, shown only for this case:
   - "See plans" opens https://folderbird.com/Pricing?utm_source=windows-app&utm_medium=login&utm_campaign=device-limit. The utm tags are only for analytics. Pricing ignores `plan=`, so leave it out unless Finch also makes Pricing pre-select a plan.
   - "Manage my devices" opens https://folderbird.com/Device. Unauthenticated visitors are sent to sign in first and come back afterwards. That page has the trash button, and old "signed in elsewhere" entries count against the limit, so removing one is often the free fix.
   - On .NET Framework 4.8, `Process.Start(url)` already uses the shell. Wrap it in try/catch and fall back to copying the URL to the clipboard.
3. Make lblMessage tall enough for three or more lines, or AutoSize with a MaximumSize width of 340. Check on Windows at 100% and 150% scaling that the whole message shows.
4. How it reaches users: the PC that hits the limit is a fresh install. It gets whatever /download/windows serves, not an auto-update. The fix therefore reaches the people who need it only after:
   - a signed 1.2.8.2 or later is published with publish-release.ps1;
   - the seven DownloadController constants move together (Win* and Setup*);
   - the web build carrying them is swapped to production (Majid's go).
   Moving the AgentUpdate__* settings for the existing fleet is optional for this fix, but if the constants move, those settings must move with them (they are coupled to WinBlob).

This changes production only through that release and swap.

## 45. [subscription] After paying, the buyer returns to an unchanged Pricing page: no confirmation, and a window where a second subscription is possible
- Severity: medium · kept 2/2 · owner: Finch · live site: yes · effort: 1-2 hours
- Evidence: Pricing.cshtml:229 `successUrl: window.location.origin + '/Pricing?welcome=1'`. A grep for 'welcome' finds nothing else in Controllers/Views, so the parameter is ignored. The 'Manage subscription' state depends on `user.PaddleSubscriptionId`, which only the webhook writes (HomeController.cs:53-61, PaddleController.cs:148-152). Until the webhook lands, the buttons still read 'Choose Falcon' and open a fresh checkout (Pricing.cshtml:192-194, 216, 225). No Paddle eventCallback is registered to react to checkout.completed.
- Impact: A customer who has just paid sees the same 'Choose Falcon' page. That reads as 'did it work?', leads to support emails, and allows a duplicate charge if they click again. They also miss the next step (add the third PC).
- Fix: Point successUrl at /Manage?welcome=1, or handle welcome=1 on Pricing with a banner ('Thanks — your Falcon plan is being activated; this page updates in a few seconds') that polls a small /Manage/PlanJson until Tier changes. Disable the buy buttons while welcome=1. Add a Paddle eventCallback for checkout.completed that shows the same message.
- Reviewer correction: Keep `successUrl` on /Pricing?welcome=1 and handle it there.
1. When `welcome=1` and the user is signed in, render a banner: "Thanks — your plan is being activated. This page updates by itself." Treat the page as managed at once: buy buttons become 'Manage subscription', and fbSubscribe never opens checkout.
2. Poll a new small `[Authorize]` GET (for example /Manage/PlanJson returning tier, subStatus and hasSub from AspNetUsers) every 3 s for up to about 60 s. Swap the banner to "You're on Falcon — up to 6 PCs. Add your next PC: /Download" once Tier changes. After the timeout, say "Activation is taking longer than usual; your receipt is in your email" and link /Contact.
3. Register Paddle `eventCallback` on `checkout.completed`. It should set a sessionStorage flag that disables checkout in every open tab of the session.
4. Make fbSubscribe re-check the server (the same PlanJson) before calling Paddle.Checkout.open, so a stale second tab cannot start a second subscription.
5. Separate bug in the same block: `document.querySelectorAll('.btn-buy')` also relabels the Sparrow 'Get started' and Phoenix 'Enterprise options' links as 'Manage subscription' while their hrefs still go to /Account/Register and /EnterpriseSolutions. Scope the selector to `button.btn-buy`.

Owner: Finch. A push to main deploys to staging; the change reaches production only on a swap. Effort: about 1-2 hours plus one sandbox checkout to verify. | 1. **Handle `welcome=1` on the Pricing page itself.** Keep `successUrl` as /Pricing?welcome=1. When the query is present and the user is signed in, HomeController.Pricing sets ViewBag.Welcome = true. The view shows a banner: "Thanks, your payment went through. Your plan is being activated; this page updates in a few seconds. A receipt is on its way from Paddle."
2. **Block a second checkout in the same page load.** While Welcome is true, render the page as if subscribed. Set `P.managed` (or a new `P.pending`) so the buy buttons read "Activating…" and are disabled, and make `fbSubscribe` return early instead of calling `Paddle.Checkout.open`.
3. **Poll the right field.** Add a small signed-in GET, for example /Manage/PlanJson, that returns `{ hasSub: !string.IsNullOrEmpty(PaddleSubscriptionId), status: SubStatus, tier: Tier, limit: DeviceLimit }`. The banner polls it every 2-3 seconds for up to about 60 seconds. When `hasSub` turns true, switch the buttons to "Manage subscription" and show the new tier once it arrives. Base the button state on `hasSub`, not on Tier.
4. **Add a fallback.** After about 60 seconds without `hasSub`, say "Still processing. Check your email receipt or contact info@folderbird.com; please don't buy again." Then replace the buttons with that contact link. Do not offer checkout again.
5. **Optional extra guard.** In `fbSubscribe`, fetch PlanJson once before opening checkout and refuse if `hasSub` is true. This covers a stale tab opened before the purchase.

**Owner:** Finch.

**Production:** Merging to main deploys to staging only. It reaches the live site with the next swap.

**Effort:** about 1-2 hours, plus a Paddle sandbox test to see the real webhook timing.

## 46. [subscription] No purchase conversion is sent to Google Ads, so ad spend can never be optimised toward paying customers
- Severity: medium · kept 2/2 · owner: Wren (conversion action in the ads console); Finch (page code) · live site: yes · effort: Console: 10 minutes. Code: about 1 hour
- Evidence: The only Ads conversion in the codebase is the sign-up one: ConfirmEmail.cshtml:20 `Cfg["GoogleAds:ConfirmSignupLabel"]` and line 99 `gtag('event','conversion',…)`. Pricing.cshtml has no gtag call and no Paddle eventCallback, and appsettings.example.json:68-73 defines only ConfirmSignupLabel.
- Impact: Google Ads reports 0 conversions and spends SAR 114 a night blind. Even after a sale it cannot learn which clicks pay. Revenue per campaign is invisible.
- Fix: Wren creates a 'Purchase' conversion action in Google Ads (AW-1017057167) and hands over its label. Finch adds a GoogleAds__PurchaseLabel setting, fail-safe while unset, and fires gtag('event','conversion',{send_to, value, currency, transaction_id}) from Paddle's checkout.completed eventCallback, behind the same consent guard ConfirmEmail uses.
- Reviewer correction: Do this first: Majid or Wren confirm in App Service that GoogleAds__ConfirmSignupLabel is set to a real conversion label on production (a sticky setting). Without it no conversion of any kind can be recorded, and it is a settings change with no deploy.

Then add the purchase conversion:

1. Wren creates a 'Purchase' conversion action under AW-1017057167 and hands over its label.

2. Finch adds a GoogleAds__PurchaseLabel setting. While it is unset, nothing is emitted. It gets the same `^[A-Za-z0-9_-]{1,64}$` shape check and Json.Serialize as ConfirmEmail.cshtml. In Pricing.cshtml, pass an eventCallback to Paddle.Initialize. On `checkout.completed`:
   - send `gtag('event','conversion',{send_to:'AW-1017057167/'+label, value: data.totals.total, currency: data.currency_code, transaction_id: data.transaction_id, event_callback: go, event_timeout: 2000})`. Check these Paddle field names against Paddle Billing's documented checkout.completed payload before relying on them.
   - `transaction_id` must be Paddle's transaction id, not the user id, so separate purchases stay separate.
   - Keep the `typeof gtag === 'function'` consent guard. Without consent, call `go()` straight away.
   - `go()` navigates to /Pricing?welcome=1.
   - Remove `successUrl` from Checkout.open (or rely on the callback instead) so Paddle's redirect cannot cancel the beacon.

3. Never fire the conversion just because ?welcome=1 is in the URL; anyone can type it.

A sturdier option, about half a day: send the conversion from PaddleController's verified `transaction.completed` webhook through Google Ads offline/enhanced conversion import. It is server-verified and does not depend on the browser or the page staying open. It needs the gclid stored at sign-up and Majid's decision on consent and legal.

This changes the live site once deployed and swapped. Effort: console about 10 minutes; client-side code about 1-2 hours; webhook route half a day or more. | 1. Do the signup half first. Wren creates the signup conversion action. Majid (or Falcon) sets the App Service setting `GoogleAds__ConfirmSignupLabel` on production, which needs no redeploy. The existing fail-safe code then starts reporting confirmed sign-ups.
2. For purchases, Wren creates a separate 'Purchase' action and hands over its label. Finch adds `GoogleAds:PurchaseLabel` to appsettings.example.json and renders it into Pricing.cshtml with the same shape check as ConfirmEmail (`^[A-Za-z0-9_-]{1,64}$`, `@Json.Serialize`). It emits nothing while the setting is unset.
3. Pass `eventCallback` to the existing `Paddle.Initialize` call (or use `Paddle.Update({eventCallback})`). On `ev.name === 'checkout.completed'`, build `gtag('event','conversion',{send_to:'AW-1017057167/'+label, value: <total from ev.data.totals>, currency: ev.data.currency_code, transaction_id: ev.data.transaction_id})`. Check the units of the totals against a sandbox event before trusting the value.
4. Guard it the same way ConfirmEmail does: call it if `typeof gtag==='function'`, otherwise push it to `window.fbAfterGtag`. With basic Consent Mode it then only counts visitors who accepted cookies.
5. Stop the redirect from dropping the hit. Either remove `successUrl` and navigate to `/Pricing?welcome=1` from gtag's `event_callback`, with a timeout of about 2 s as a fallback. Or keep `successUrl` and fire the conversion on the welcome page, but only from a server-rendered flag set once the Paddle webhook has recorded the subscription. A bare `?welcome=1` can be typed by anyone.
6. Changing Pricing.cshtml changes the live checkout page, so test it once against Paddle sandbox on staging before swapping. Effort: about 1-2 hours of code and test, plus about 10 minutes in the Ads console.

## 47. [subscription] When paddle.js fails to load, the page shows a sales-policy message ('we're onboarding subscribers personally') instead of naming the real problem
- Severity: low · kept 2/2 · owner: Finch · live site: yes · effort: 1 hour
- Evidence: Pricing.cshtml:159 loads `https://cdn.paddle.com/paddle/v2/paddle.js`. At 219-222, `if (!priceId || !P.token || !window.Paddle) { … showContact(tier); return; }` shows the overlay at 138-140: 'We're onboarding new subscribers personally for now. Email us and we'll get your plan started — usually within a day.' The reason is printed only to the browser console (168-181). The async checkout error is not caught: line 231 catches only synchronous throws.
- Impact: A buyer whose ad or privacy blocker, or an in-app browser, blocks cdn.paddle.com is told checkout is a manual email process. Almost nobody emails. A buyer who would have paid in 30 seconds is lost, and the team never hears about it. Whether common blockers or the Facebook in-app browser block it is unknown.
- Fix: Distinguish the cases. If config is missing, keep the email overlay. If window.Paddle is missing, show 'The secure checkout couldn't load — it may be blocked by an ad blocker or this app's built-in browser. Open folderbird.com/Pricing in Chrome or Safari, or email us.' with a copy-link button. Also send a beacon (or a gtag event) so the team can count these failures.
- Reviewer correction: The direction is right. Four adjustments:

1. **Split the line 219 condition into three cases.**
   - `!priceId || !P.token`: a configuration gap. Keep the email overlay.
   - `!window.Paddle`: show a separate message, roughly "Secure checkout couldn't load. An ad or privacy blocker, or this app's built-in browser, may be stopping it. Open folderbird.com/Pricing in Chrome or Safari, or email us." Add a copy-link button.
   - `Paddle.Initialize` threw (line 188): set a flag in that catch and treat it like the `!window.Paddle` case.

2. **Don't count these failures with gtag.** GA4 on this site is consent-gated and already undercounts. Instead, `navigator.sendBeacon` a small POST to a new, anonymous, rate-limited endpoint that only writes a log line, so the failure shows up in AppRequests or the console log. Alternatively, accept that it stays uncounted. Never send the user's email or id in it.

3. **Pass an `eventCallback` to `Paddle.Initialize`** that logs `checkout.error`. That covers the async errors the line 231 catch cannot see.

4. **Keep the overlay's styles inline** and add dark-theme colours. The current overlay hardcodes `#fff`.

Owner is Finch. It reaches the live site only after a push to main (which deploys to staging) and then a swap. Effort is about 1 to 2 hours with the beacon endpoint, or about 30 minutes for the copy split alone. | Keep the fix as proposed, with three adjustments.

1. Detection is reliable. The script tag is synchronous, so by the time the click handler runs, `window.Paddle` is either defined or its load already failed. Show the "checkout couldn't load" message only when `P.token` and `priceId` are present but `!window.Paddle`. Keep the email overlay for the config-missing case. Both messages must keep the mailto link.

2. Do not count these failures with gtag. GA4 is consent-gated on this site and already undercounts. Make a same-origin request instead, so the event shows in AppServiceHTTPLogs with no new endpoint. For example, `navigator.sendBeacon('/Pricing?checkout=paddle-blocked&tier=' + tier)`. The Pricing action routes any HTTP method, so this needs no server change. It costs one extra page render per blocked click.

3. Optional: add an `eventCallback` to `Paddle.Initialize` that logs a `checkout.error` event the same way. This covers the asynchronous failures the try/catch cannot see.

Effort is about 1 hour, and the change goes to staging first. It reaches production only after a swap.

## 48. [subscription] Do NOT run the live test purchase on Majid's account: it is reset to Phoenix/999 at every start-up and the webhook will lock his devices
- Severity: low · kept 1/2 · owner: Majid · live site: yes · effort: No code. Adds 5 minutes to the test
- Evidence: Program.cs:625 `UPDATE dbo."AspNetUsers" SET "Tier" = 'phoenix', "DeviceLimit" = 999 WHERE lower("Email") = 'Majid's own account';` runs on every start-up. A purchase on that account runs MapPrice → falcon/6 and `LockExcessDevices(resolvedUid, limit)` (PaddleController.cs:95-98, 170-187), which locks every unlocked device except the 6 newest. A refund or cancel later sets limit 2 and locks all but 2. The start-up reset restores DeviceLimit 999 but never unlocks devices (unlocking is manual, comment at line 169).
- Impact: The recommended end-to-end checkout test, done the obvious way, would lock some of Majid's production devices (the project notes list 7 for his account) and produce a confusing result that then 'fixes itself' on the next restart.
- Fix: Run the real-card test with a new throwaway account that has 0-1 devices. If Majid's own account has already been used, check Devices.Locked for that user afterwards and unlock from My Devices.
- Reviewer correction: Run the real-card Falcon test on a new throwaway account (Sparrow tier, 0-1 devices), never on Majid's own account. Then check the result in the database: Tier = falcon and DeviceLimit = 6 on that account, plus a "[PADDLE] subscription.activated ... tier=falcon" console line. Do not judge it from the account page after a restart. Cancel the test subscription in the Paddle portal and refund it afterwards. Expect the account to drop to sparrow/2, which also proves the downgrade path.

If Majid's own account was already used for a purchase:
1. Cancel that subscription in Paddle, so renewal events don't keep re-applying falcon/6.
2. Wait for a restart, or trigger one, so DeviceLimit is back at 999.
3. Unlock his devices from My Devices. Before the restart, ToggleDeviceLock caps unlocking at the temporary limit.

Owner: Majid. No code change. It touches production data only through the test itself. Effort: about 5-10 extra minutes. | Not a funnel fix. Put a note in the checkout-test instructions: use a new throwaway account with 0-1 devices for the real-card Falcon test. Check the result in the console log `[PADDLE] subscription.activated ... -> tier=falcon limit=6` and in the account row soon after the webhook, because Majid's own account is reset to phoenix/999 at every start-up. If Majid's own account was used anyway, unlocking from My Devices only works after the next restart restores limit 999, because ToggleDeviceLock refuses it until then. Before that, unlocking means locking another device first, or a direct update to Devices.Locked by someone with database access. Owner: Majid. No code, live-site test only, about 5 extra minutes.

## 49. [subscription] Changing a Paddle price later silently downgrades every existing subscriber on it and locks their devices
- Severity: low · kept 2/2 · owner: Finch · live site: yes · effort: 30 minutes
- Evidence: PaddleController.cs:113-120: MapPrice returns ('sparrow', 2) for any price id that does not equal one of the four configured Paddle:Prices values. Line 95 applies it on every non-created event (activated, updated, resumed, and renewal updates), and line 98 then runs LockExcessDevices. A subscriber on an older pri_ id whose renewal sends subscription.updated after the setting has been changed to a new price is mapped to Sparrow.
- Impact: There are no subscribers yet. But the first price change (a discount, a new yearly price, a regional price) would downgrade paying customers on their next billing event.
- Fix: Map unknown price ids to 'leave tier unchanged and log at error level' instead of Sparrow, or keep a list of legacy price ids per tier (for example Paddle:Prices:FalconLegacy). Only canceled/paused should ever drop to Sparrow.
- Reviewer correction: Owner: Finch. Changes production (the webhook code). Effort about 1 hour including a test.

1. Map by Paddle product, not by price. A replacement price stays under the same product. Read items[].price.product_id (pro_...) from the webhook and compare it with new settings Paddle:Products:Falcon and Paddle:Products:Eagle. Keep the four price ids as a fallback.
2. If neither the product nor the price is recognised, set changeTier=false: leave Tier and DeviceLimit as they are and do NOT call LockExcessDevices. Still record SubStatus and RenewsAt, and log at error level with the price and product ids so the gap is visible. Do the same when the price id is empty. A first activation with an unknown id then leaves a new user on their default (Sparrow), which is safe, and an existing payer keeps the tier they paid for.
3. Only canceled or paused should drop a user to Sparrow, as the code already does at line 90.
4. Add a test: a subscription.updated with an unrecognised pri_ must not change Tier and must not lock any devices.

Until this ships, add a release rule: never remove an old price id from Paddle:Prices while any subscriber is still on it. | Refine the fix in PaddleController.cs in four ways:

1. **Unknown price: change nothing.** For a non-empty price id that matches no known id, set `changeTier = false`, so neither UpdateUserEntitlement's Tier/DeviceLimit columns nor LockExcessDevices runs. Log `[PADDLE] ERROR unknown price <id> for sub <id>` loudly. Keep the canceled/paused branch (line 90/93) as the only path that drops to Sparrow.
2. **Keep a list of legacy ids per tier.** Add a list setting such as `Paddle:Prices:FalconLegacy` / `EagleLegacy` (comma-separated `pri_` ids) and match against it in MapPrice. Then a deliberate price change keeps old subscribers on the right tier without manual action.
3. **Treat a missing price id as unknown.** Also treat a null or empty `priceId` on a non-downgrade event as "unknown, change nothing" rather than Sparrow.
4. **Don't let a new customer on an unmapped price go unnoticed.** With rule 1, an `activated` event for a new customer on an unmapped price grants nothing (they stay on Sparrow after paying). That is safer than a downgrade, but it must page someone, for example through the existing `folderbird-oncall` alerting or a daily-report line. A silent log line alone would let it sit unnoticed.

This is a web change that needs a production deploy: Finch, about 30-60 minutes.

## 50. [subscription] (Cross-stage, install) The Windows app's sign-in window has no 'Create account' link; a visitor without an account sees 'Incorrect email or password'
- Severity: high · kept 2/2 · owner: Swift · live site: yes · effort: 1 hour of code, plus a signed Windows release
- Evidence: folderbird-agent FileRouteClient/LoginForm.Designer.cs:33-48: the controls are a header, email, password, show-password, remember-email, message label, Sign In button, progress bar and footer ('This device'). There is no register or forgot-password link. LoginForm.cs:145-150: LoginFailed shows 'Incorrect email or password. Please try again.'
- Impact: This matches the measured night: 3 ad visitors downloaded the installer and 0 registered. Someone who installs first meets a sign-in window with no way to create the account that is required before any free or paid plan.
- Fix: Add 'New to Folderbird? Create a free account' (opens /Account/Register?from=app) and 'Forgot password?' links under Sign In. After a LoginFailed, also show 'No account yet? Create one free'.
- Reviewer correction: Swift (Windows app):
- Add two LinkLabels under btnLogin: "New to Folderbird? Create a free account" and "Forgot password?".
- Open them with `Process.Start(new ProcessStartInfo(url) { UseShellExecute = true })`, the same pattern as `MyCustomApplicationContext.cs:610`.
- Build the URLs from `Utils._BASEURL` with the trailing "/api" removed, plus `/Account/Register?from=app` and `/Account/ForgotPassword`, so test-profile copies open staging, not production.
- The form is 404x404 and the footer sits at y=374, so make the form about 30-40px taller rather than squeezing the links in.
- In the "LoginFailed" case, add "No account yet? Create one free" to the message (or show the register link) and keep the password reselect.
- Make "Reset your password" in the LockedOut message a working link too.
- Change nothing on the server: no new reply code, because deployed apps save any unknown reply as their device token and a distinct reply would reveal which emails exist.
- Ship as a signed release numbered above 1.2.8.1, with AssemblyVersion equal to AssemblyFileVersion. Signing needs Majid's SSL.com password and one-time codes.
- Effort: about 1-2 hours of code, then the signing and release run.

Finch (website), optional, can go live in minutes without waiting for the app release: after someone clicks the Windows download on /Download, show "Next: create your free account" with the register link. Today that prompt only appears in step 2, below the hero. | Owners: Swift for the app code, Majid for signing and publishing, Finch for the web half.

App change, to ship as 1.2.8.2 or later. The version must be strictly higher than 1.2.8.1, with AssemblyVersion equal to AssemblyFileVersion, or the fleet updater ignores it.
1. Add two LinkLabels under Sign In: "New to Folderbird? Create a free account" and "Forgot password?".
2. Point them at `<site>/Account/Register?utm_source=windows-app&utm_medium=signin` and `<site>/Account/ForgotPassword`. ForgotPassword exists (`Views/Account/ForgotPassword.cshtml`).
3. Derive `<site>` from the same server base the app already talks to. In profile mode use `Utils.ProfileBaseUrl()` with `/api` stripped, so a staging test copy never sends people to production.
4. Do not use `?from=app` unless AccountController reads it. Nothing reads it today, so it would measure nothing. UTM parameters at least show up in the HTTP logs and GA4.
5. Open the link with `Process.Start(url)` (shell execute) inside try/catch.
6. On `LoginFailed`, change the copy to "Incorrect email or password, or there is no Folderbird account for this email yet." and show the create-account link prominently. The server answers `LoginFailed` for an unknown email, so the app cannot tell those two cases apart.

Effort: about 1 hour of code. Then Majid runs `publish-release.ps1` and the AgentUpdate arming order; the fix reaches new installs only after that.

Web half, which can go live sooner because it needs no signed release:
- On /Download, put "Create your free account first" next to or ahead of the Windows button. Today the hint sits in step 2's small print.
- Or, after the installer download starts, show a register prompt.
- This changes the live site after the usual staging, then swap. Effort: under an hour.

## 51. [subscription] (Cross-stage, landing) The landing hero and the Register page never say the product is free
- Severity: medium · kept 2/2 · owner: Finch · live site: yes · effort: 15-30 minutes
- Evidence: A grep -i 'free' over Views/Home/AlternateHome.cshtml finds only line 1225 (the Android note) and a code comment. The hero (828-836) says 'Install one small app, sign in…' with no price. The only '$0' is invisible JSON-LD (line 66). Views/Account/Register.cshtml has no 'free', 'plan' or 'card' wording at all.
- Impact: About 111 ad visitors reached '/' and only 5 opened Pricing. The rest never learned there is a free-forever plan with no card, which is the strongest reason to try a remote-access app from an ad.
- Fix: Add one line to the hero CTA area and the Register page: 'Free for up to 2 PCs — no credit card. Upgrade only if you add more.' with a link to /Pricing.
- Reviewer correction: Mostly sound; fix the wording and where it goes. (1) Match Pricing's terms: Pricing says "2 devices" and the limit counts registered PCs (phones are not device rows). So write "Free for 2 computers, forever. No credit card." and link it to /Pricing. Don't invent a different noun: "PCs" in one place and "devices" in another will read as two different limits. (2) Landing: add it as a fifth item in the existing `.hero-proof` strip (AlternateHome.cshtml ~840-845) or as a line under `.hero-cta`. The proof strip is the cheapest place and keeps the layout: one `<span>`, no new CSS. Also add the same phrase to the CTA band paragraph (line 1247). (3) Register.cshtml: one muted line under the "Create your Folderbird account" heading (line 12), e.g. "Free for 2 computers, no credit card. Upgrade only if you add more." with a link to /Pricing. Use Bootstrap theme tokens (text-body-secondary), never an inline colour. (4) After the edit, run `python3 render_landing.py` + `node check-landing.js` (and the 412px check), because the hero strip wraps on phones. Owner: Finch. It lands on staging when pushed to main and reaches production only on Majid's swap. Effort: 20-40 minutes including the landing check. | The fix is right. Four adjustments:

1. Use the Pricing page's own words so the pages cannot disagree: "Free forever for up to 2 computers, no credit card. Pay only if you add more." Say "computers", not "PCs": the device limit also counts Linux boxes, and the hero already lists Linux (beta).

2. On the landing page, put the line just below `.hero-cta` (around line 836) and also in the closing CTA band (around line 1245), with a link to /Pricing. The hero has a dark blue background, so give the line light text, like `.hero-proof`'s rgba(255,255,255,.92). Do not use a light inline background or var(--muted). Check it in both themes and at 412px.

3. On Register.cshtml, put the line under the "Create your Folderbird account" heading as `text-body-secondary small`. Use a theme token, not an inline colour, so it follows dark mode.

4. CLAUDE.md requires `python3 render_landing.py && python3 serve.py &`, then `node check-landing.js`, after any landing-page edit. The hero is also in the landing screenshots. Allow 30-60 minutes including that check, not 15-30. It reaches production only after a swap.
