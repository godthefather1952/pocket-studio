# Pocket Studio

An on-device AI image studio for iPhone, inspired by [Open Generative AI](https://github.com/anil-matcha/open-generative-ai) but rebuilt natively for iOS. Everything runs locally on the iPhone's Neural Engine with Apple's [Core ML Stable Diffusion](https://github.com/apple/ml-stable-diffusion). There's no cloud API, no account and no API key.

**Features**
- Text-to-image (Stable Diffusion 1.5, 512×512)
- Photo-to-image: restyle a photo from your library
- Steps, prompt strength, seed and sampler controls
- A gallery that also shows up in the Files app, plus Save to Photos and Share
- Import other compiled Core ML SD 1.x/2.x models from Files

You download the model once (about 1.6 GB) inside the app. After that, generating works in airplane mode.

**Requirements:** iOS 17+, and an iPhone 15 Pro / 16 / 16 Pro or newer is recommended (8 GB RAM). Video generation isn't supported because current video models need far more memory than iOS gives an app.

## Install with AltStore

Every push to `main` builds an unsigned `PocketStudio.ipa` on GitHub's Macs. You can find it under **Releases**, and AltStore signs it with your Apple ID.

1. **Set up AltStore once.** Install AltServer on a Mac or Windows PC from [altstore.io](https://altstore.io) and use it to install AltStore on your iPhone. On the iPhone, turn on Settings → Privacy & Security → **Developer Mode** and restart.
2. **Download the IPA.** On your iPhone, open this repo's **Releases** page in Safari, tap `PocketStudio.ipa`, then tap **Download**.
3. **Install it.** Open AltStore → **My Apps** → **+** → pick `PocketStudio.ipa` from Downloads. Your iPhone needs to be on the same Wi-Fi as the computer running AltServer.
4. **First launch.** Go to **Models** → **Download** (use Wi-Fi and keep the app open). The first image after that takes 1–3 minutes while iOS prepares the model for the Neural Engine. After that, each image takes seconds.

With a free Apple ID, sideloaded apps expire after 7 days. AltStore refreshes them automatically when AltServer is reachable, or you can open AltStore and tap **Refresh All**. Your models and images stay put.

## Build it yourself (Mac)

```sh
brew install xcodegen
xcodegen generate
open PocketStudio.xcodeproj   # pick your team in Signing & Capabilities, then Run
```
