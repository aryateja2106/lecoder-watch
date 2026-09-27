# install/payload/rmux-bridge/public/vendor/ — a copied-in third-party terminal library (xterm.js), minified

**Surface:** web
**Prove a change:** `sh scripts/check-phone-input-and-wake.sh` (asserts an input attribute inside `xterm.js`, `scripts/check-phone-input-and-wake.sh:28,84`)
**Traps:** do not hand-edit (each `.js` is one minified line); the upstream version is not recorded anywhere (unverified); a replacement must keep the attribute that check greps for.
