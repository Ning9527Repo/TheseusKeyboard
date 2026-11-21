// Copyright 2026 Ning.
// Material extracted from TheseusTabBar (Vadim Drobinin, Apache-2.0).
// Compile in the same Swift module as the pinned Theseus sources.
// New implementation: no code/assets from the deleted keyboard project.
import UIKit
import QuartzCore

/// The demo's background material only: no items, lens or selection control.
/// Its host must contain BACKGROUND ONLY; never attach above keyboard keys.
@objc(NTKGlassBackground)
public final class NTKGlassBackground: UIView {
    private let glass: TheseusView
    private weak var backgroundHost: UIView?
    private var appliedDark: Bool?
    private var appliedSpectrum: CGFloat?
    private var appliedBounds = CGRect.null
    private var renderScheduled = false
    private var isSuspended = false
    private var followsHostCorner = true

    public override init(frame: CGRect) {
        var config = TheseusConfiguration()
        // TheseusTabBar.swift 360...373: the background, NOT the selected lens.
        config.blur.radius = 18
        config.captureMethod = TheseusCapability.isDeviceSupported ? .layerRendering : .surfaceBased
        config.refraction.edgeWidth = 0
        config.refraction.interiorSharpness = 0.48
        config.refraction.interiorAverage = 80
        config.refraction.dispersion = 0
        config.theme.neutralBodyScale = 1
        config.outerGlow = 0
        config.edgeFeather = 1.0 / 3.0
        glass = TheseusView(configuration: config)
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        clipsToBounds = true
        glass.isUserInteractionEnabled = false
        glass.continuousUpdate = false
        // No other glass captures this view, so no CPU frame readback needed.
        glass.providesCaptureSnapshot = false
        glass.setCaptureExcludedViews([self])
        addSubview(glass)
        NotificationCenter.default.addObserver(self, selector: #selector(materialChanged),
            name: TheseusSettings.settingsDidChangeNotification, object: nil)
        updateMaterial()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Source must be a dedicated native background subtree, not a keyboard root.
    /// Excluding this overlay leaves native background available for capture.
    @objc(attachToBackgroundHost:sourceView:)
    public func attach(to host: UIView, sourceView: UIView) {
        precondition(Thread.isMainThread)
        guard host !== self, !host.isDescendant(of: self),
              sourceView !== self, !sourceView.isDescendant(of: self) else { return }
        if glass.sourceView !== sourceView { glass.sourceView = sourceView }
        if backgroundHost !== host || superview !== host {
            backgroundHost = host
            host.addSubview(self)
        }
        frame = host.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        setNeedsLayout()
        scheduleRender()
    }

    @objc public func nativeBackgroundDidChange() {
        precondition(Thread.isMainThread)
        scheduleRender()
    }

    @objc public func setSuspended(_ suspended: Bool) {
        precondition(Thread.isMainThread)
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        updateActivity()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updateActivity()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if followsHostCorner, let host = backgroundHost {
            layer.cornerRadius = host.layer.cornerRadius
            layer.cornerCurve = host.layer.cornerCurve
        }
        glass.frame = bounds
        let corner = layer.cornerRadius
        if glass.shape.cornerRadius != corner { glass.shape.cornerRadius = corner }
        // Do not force the tab bar's height/2 capsule onto a keyboard rectangle.
        if appliedBounds != bounds {
            appliedBounds = bounds
            scheduleRender()
        }
        updateMaterial()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateMaterial()
    }

    @objc private func materialChanged() {
        updateMaterial()
        scheduleRender()
    }

    private func updateActivity() {
        if window == nil || isSuspended || isHidden {
            glass.pauseRendering()
        } else {
            glass.resumeRendering()
            scheduleRender()
        }
    }

    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.renderScheduled = false
            guard self.window != nil, !self.isSuspended, !self.isHidden,
                  self.bounds.width > 0, self.bounds.height > 0 else { return }
            self.glass.invalidateBackground()
        }
    }

    private func updateMaterial() {
        let dark = traitCollection.userInterfaceStyle == .dark
        let spectrum = TheseusSettings.shared.tintSpectrum
        guard appliedDark != dark || appliedSpectrum != spectrum else { return }
        appliedDark = dark
        appliedSpectrum = spectrum
        let chrome = NTKTabBarChrome.material(isDark: dark, spectrum: spectrum)
        var config = glass.configuration
        config.theme.isDark = dark
        config.theme.neutralBodyScale = 1
        config.theme.bodyCurve = chrome.knots
        config.theme.bodyCurveChromaSlope = chrome.chromaSlope
        config.theme.bodyCurveSaturation = 1
        config.theme.backdropSaturation = chrome.chroma
        config.theme.backdropGain = 1
        config.theme.luminanceLift = 0
        config.refraction.interiorSharpness = dark ? 0.42 : 0.48
        glass.configuration = config
        scheduleRender()
    }
}
