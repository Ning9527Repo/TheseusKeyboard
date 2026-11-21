# Theseus Keyboard 0.1.0-test3 — native backdrop placement repair

Theseus TabBar's iOS27 central background glass material, adapted to the native system keyboard background. No tab items, lens, icons or keyboard input changes. This is a fresh project, not a continuation of the deleted project.

- Author: **Ning&Vadim Drobinin**
- Upstream: [valzevul/Theseus](https://github.com/valzevul/Theseus), pinned at `71ca1c127a4e7fe3387361f160c4890dbd427f66`
- Target for this test: **RootHide / iphoneos-arm64e only**, iOS 15+
- User requested test despite known backdrop-capture limitations: see [TESTING.md](TESTING.md).
- Sources and shaders from upstream are unmodified and checked against `vendor/Theseus/UPSTREAM.json`; Apache-2.0 LICENSE and NOTICE are retained there.

Manual GitHub Actions only. On macOS with Xcode and Metal toolchain: `python3 tools/build.py`.

Successful compilation, ad-hoc signature and package checks do not prove visual correctness or successful cross-process backdrop sampling. No automatic install, injection or respring.
