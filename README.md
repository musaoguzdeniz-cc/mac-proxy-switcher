# Mac Proxy Switcher

A native macOS menu bar app for setting the HTTP and HTTPS proxies on a network service, switching between saved profiles, and restoring the previous settings.

## Install

Download **Mac-Proxy-Switcher-macOS-universal.zip** from [GitHub Releases](https://github.com/musaoguzdeniz-cc/mac-proxy-switcher/releases), unzip it, and move **Mac Proxy Switcher.app** into Applications. The Universal build targets macOS 13 Ventura and later on Apple silicon and Intel.

The preview uses a local ad hoc signature. It has no Developer ID signature or Apple notarization, so Gatekeeper may block it on first launch. See [Apple's guidance on opening apps safely](https://support.apple.com/102445).

## Use

1. Open the network icon in the menu bar and select a network service, such as Wi-Fi or Ethernet.
2. Enable HTTP, HTTPS, or both. Enter each proxy hostname or IP address and port. For a shared endpoint, select **Use the HTTP address for HTTPS**.
3. Select **Apply**. macOS may ask you to authorize the change. Use **Restore previous** to undo the last change for this service.
4. Enter a name and select **Save profile**. Later, select it under **Apply profile** to apply it to the currently selected service. A profile with both switches off disables both manual web proxies.

**Test connection** sends a request to `example.com` through each enabled endpoint in the editor, including unsaved edits. It tests HTTP forwarding and HTTPS tunneling through a standard HTTP proxy. Apps that use macOS proxy settings pick up the configured service settings. Existing automatic proxy settings and bypass rules can affect which proxy those apps use.

This release supports manual, unauthenticated web proxies. Profiles are stored locally. The app preserves the service's PAC, automatic discovery, SOCKS, and bypass settings.

## Build from source

On a Mac with the Xcode command-line tools installed, run:

```bash
bash scripts/build.sh
```

The app and ZIP archive are written to `build/`. GitHub Actions runs proxy settings tests, builds both architectures, and verifies the bundle's signature.

## Türkçe

Menü çubuğundaki ağ simgesine tıkla ve Wi-Fi veya Ethernet servisini seç. HTTP ve HTTPS için sunucu adresini ve portu girip **Apply** düğmesine bas. **Save profile** ile ayarları kaydedebilir, **Apply profile** ile yeniden uygulayabilir ve **Restore previous** ile seçili servisin önceki ayarlarına dönebilirsin.
