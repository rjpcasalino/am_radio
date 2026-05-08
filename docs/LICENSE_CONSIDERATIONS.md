# License and App Store Distribution Considerations

This document outlines important considerations for distributing AM Radio under the BSD 3-Clause License, especially for app store distribution.

## BSD 3-Clause License Benefits

The BSD 3-Clause License was chosen because it:

1. ✅ **Allows commercial distribution** - You can sell the app on any app store
2. ✅ **Allows free copying** - Anyone can fork, modify, and redistribute
3. ✅ **Protects your name** - Clause 3 prevents others from using your name to promote derivatives without permission
4. ✅ **Simple compliance** - Only requires including the license text
5. ✅ **App store compatible** - Apple App Store, Google Play, and others accept BSD-licensed apps

## Key Considerations for App Store Distribution

### 1. **Trademark Protection (Built into BSD-3)**

The BSD 3-Clause License includes an important clause that MIT doesn't have:

> "Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission."

**What this means:**
- Others can fork your code and create competing apps
- However, they **cannot** use your name ("rjpcasalino" or "am_radio" depending on trademark) to promote their version
- You should consider trademarking "AM Radio" if you want stronger brand protection

**Recommendation:** If you sell on app stores, consider registering "AM Radio" (or your chosen app name) as a trademark. This provides stronger protection than the license alone.

### 2. **Dependency License Compatibility**

All your dependencies are compatible with commercial distribution:

**Perl CLI Dependencies:**
- `mpv` (GPL/LGPL) - ✅ **Safe**: You invoke it as an external program, not linking against it
- `curl` (MIT-like) - ✅ Compatible
- `ffprobe` from FFmpeg (LGPL) - ✅ **Safe**: External program invocation
- Perl core modules - ✅ Artistic/GPL dual-licensed, compatible

**Flutter/Mobile Dependencies:**
- Flutter SDK (BSD-3-Clause) - ✅ Compatible
- `http` (BSD-3-Clause) - ✅ Compatible
- `provider` (MIT) - ✅ Compatible
- `just_audio` (MIT) - ✅ Compatible
- `shared_preferences` (BSD-3-Clause) - ✅ Compatible

**Important Note on GPL/LGPL (mpv, ffprobe):**
Since you execute `mpv` and `ffprobe` as **separate processes** (not dynamically linking), you are NOT creating a derivative work under GPL/LGPL terms. Your BSD-licensed code remains BSD-licensed. Users need to install mpv separately on Linux anyway.

### 3. **AI-Generated Code Disclosure**

**Legal Status:**
- You own the copyright on AI-generated code that you created/directed
- No special licensing requirements for AI-generated content
- Current law (US/EU as of 2026) treats AI as a tool, not an author

**Transparency Options (Optional):**

You could add a note to your README acknowledging AI assistance:

```markdown
## Development

Parts of this codebase were developed with assistance from AI tools.
All code is original work and is licensed under the BSD 3-Clause License.
```

This is **optional** but demonstrates transparency. There's no legal requirement to disclose AI usage.

### 4. **Radio Stream Content License**

**Important:** Your app plays radio streams from third-party stations via radio-browser.info API.

**Key Points:**
- The **stream content** is NOT covered by your BSD license
- The **code** that plays streams is BSD-licensed
- Users are responsible for their own listening (personal use is generally fine)
- Station metadata is provided by radio-browser.info under their terms

**Radio-Browser.info Terms:**
- Free API, no authentication required
- No commercial restrictions on using the API
- Station data is community-contributed

**Recommendation:** Add a disclaimer in your app or README:

```markdown
## Content Disclaimer

This app provides access to internet radio streams from third-party sources
via the radio-browser.info API. The app itself is open source, but stream
content is provided by independent radio stations and is subject to their
respective copyright and licensing terms.
```

### 5. **App Store Specific Requirements**

#### Apple App Store

**Additional Requirements:**
- Privacy Policy (if you collect any data - even crash reports)
- App Store Review Guidelines compliance
- Export Compliance (encryption - likely "no" for your app)

**License Compliance:**
- Include LICENSE file in your app bundle
- Consider adding an "About" or "Legal" screen showing the license
- You may want to display licenses of dependencies (Flutter's `showLicensePage()` widget helps)

**Example Code for Flutter:**
```dart
// In your settings or about screen
TextButton(
  onPressed: () => showLicensePage(
    context: context,
    applicationName: 'AM Radio',
    applicationVersion: '1.0.0',
    applicationLegalese: 'Copyright © 2026 rjpcasalino\nLicensed under BSD 3-Clause',
  ),
  child: Text('View Licenses'),
)
```

#### Google Play Store

**Additional Requirements:**
- Privacy Policy (if you request internet permission)
- Content rating questionnaire
- Target API level requirements (Android 13+ as of 2024)

**License Compliance:**
- Same as Apple - include LICENSE in app
- Consider adding license viewer
- Play Store shows your license choice in the app listing

### 6. **Attribution Requirements**

Under BSD 3-Clause, anyone who redistributes your code (source or binary) must:

1. Include your copyright notice
2. Include the license text
3. Include the disclaimer

**For compiled apps (APK/IPA):** The license should be accessible within the app.

**Best Practice:** Add a "Licenses" or "About" screen that displays:
- Your copyright and BSD license
- All third-party dependency licenses
- Acknowledgment of AI assistance (optional)

### 7. **Protecting Your App Store Listing**

While your code is open source, you can protect your specific app store presence:

**App Name/Icon:**
- Register a trademark for your app name
- Copyright protection automatically applies to your custom icon/logo
- Store listings are yours - clones must use different names/icons

**Brand Protection Strategy:**
1. Trademark your app name (optional but recommended)
2. Use distinctive branding (your vintage bakelite color scheme is great!)
3. BSD-3 Clause 3 prevents others from using your name in marketing

**Reality Check:**
- Clones WILL appear if your app is successful
- That's the tradeoff for open source
- Focus on being the original and best-maintained version
- Community contributions can help you stay ahead

### 8. **Monetization Strategies**

With BSD-3, you have several options:

**Option 1: Paid App**
- Sell on app stores for a one-time fee
- Others can fork and release free versions
- Your advantage: official version, best support, store presence

**Option 2: Free with In-App Purchases**
- Base app is free
- Premium features (themes, advanced filters, etc.) as IAP
- More accessible, potentially higher revenue

**Option 3: Donations/Support**
- Free app with optional support button
- Link to GitHub Sponsors, Ko-fi, etc.
- Common for open source

**Option 4: Dual Store Presence**
- Official paid version on App Store
- Free F-Droid version for Android
- Different audiences, both legitimate

### 9. **Future Contributor Considerations**

If others contribute code to your project:

**Contributor License Agreement (CLA):**
- Not required for BSD-3
- Contributors retain copyright on their contributions
- All contributions are BSD-3 licensed (same as project)

**Copyright Attribution:**
- You can keep "Copyright (c) 2026, rjpcasalino" as the primary copyright
- Or update to "Copyright (c) 2026, rjpcasalino and contributors"
- Both are common for BSD projects

**Accepting Contributions:**
Your BSD-3 license allows you to:
- Accept community contributions
- Continue selling the app commercially
- No need for separate CLAs or copyright assignment

## Summary Checklist

Before distributing on app stores:

- [x] LICENSE file added to repository
- [x] README updated with license badge and information
- [ ] Add "Licenses" screen in mobile app (optional but recommended)
- [ ] Add content disclaimer about radio streams (recommended)
- [ ] Create privacy policy if needed (required by stores)
- [ ] Register trademark for app name (optional, recommended if selling)
- [ ] Set up monetization (if commercial)
- [ ] Prepare store listings with unique branding
- [ ] Test license display in production builds

## Questions to Consider

1. **App Name:** Will you keep "AM Radio" or choose a more distinctive name?
   - Generic names are harder to protect
   - Consider: "Vintage Radio", "RetroWave Radio", etc.

2. **Monetization:** How do you plan to monetize?
   - Paid app ($1.99-$4.99 is typical for niche utility apps)
   - Free with donations
   - Free with IAP for premium features

3. **Open Source Strategy:**
   - Will you accept pull requests?
   - Will you actively promote the open source aspect?
   - Consider adding CONTRIBUTING.md if you want contributors

## Additional Resources

- [Apple App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Google Play Policy Center](https://support.google.com/googleplay/android-developer/answer/9876937)
- [BSD License FAQ](https://opensource.org/licenses/BSD-3-Clause)
- [SPDX License List](https://spdx.org/licenses/) - For checking dependency licenses
- [Choose a License](https://choosealicense.com/) - License comparison tool

## Contact

For license questions or commercial partnerships, contact the copyright holder at their GitHub profile: [@rjpcasalino](https://github.com/rjpcasalino)
