import UIKit
import VisionKit

/// Photos of one line, the way Photos shows them. Each photo sits in a zooming scroll view:
/// pinch around the fingers, pan to the edges with the rubber band, double tap into the spot
/// and back. A page controller turns between them with the gap Photos has. Live Text is on
/// the image itself, so words in the photo are selectable at any zoom, and Quote takes a
/// selection into the line. The line's words live in a panel below the photo, as a caption
/// does in Photos: swipe up or press the words button and it rises while the photo moves up
/// into the room that remains; swipe down and the photo is whole again. The words are never
/// cut and never lie over the picture. One tap shows and hides the bar.
///
/// The way in and out is the system zoom transition, applied by whoever presents this.
final class PhotoViewerController: UIViewController {
    struct Photo: Equatable {
        let hash: String
        let url: URL
        /// The photo's own pixel size when the line knows it, so the fit is right before the bytes are.
        let size: CGSize?
        let thumbnail: UIImage?

        static func == (a: Photo, b: Photo) -> Bool { a.hash == b.hash }
    }

    var onClose: (() -> Void)?
    /// The line's words, changed here: edited in the panel, or a quote joined to them.
    var onWords: ((String) -> Void)?

    private(set) var photos: [Photo]
    private(set) var index: Int
    private var words: String
    /// Full-size images already decoded, by hash, so paging back costs nothing.
    private var decoded: [String: UIImage] = [:]

    private let pages = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal,
                                             options: [.interPageSpacing: 24])
    private let bar = UIStackView()
    private let closeButton = UIButton(configuration: .plain())
    private let wordsButton = UIButton(configuration: .plain())
    private let quoteButton = UIButton(configuration: .filled())
    private let countLabel = UILabel()
    private let pageLabel = UILabel()
    private let panel = WordsPanel()
    private var panelHeight: NSLayoutConstraint!
    /// The photo area reaches the top of the screen while the photo is alone, and starts
    /// below the bar while the words are up, as in Photos with the details up.
    private var pagesToTop: NSLayoutConstraint!
    private var pagesBelowBar: NSLayoutConstraint!
    private var panelShown = false
    private var chromeShown = true
    private var selection = ""

    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
    /// The vertical pull that raises the words and puts them away. It begins only for a pull
    /// upward, or for any vertical pull while the words are up; a pull down on a whole photo
    /// is not its and reaches the transition behind, which shrinks the photo back into the
    /// page. While it may begin, the transition's own recognizer is required to wait for it.
    private lazy var pull = UIPanGestureRecognizer(target: self, action: #selector(pulled(_:)))

    init(photos: [Photo], index: Int, words: String) {
        self.photos = photos
        self.index = min(max(0, index), max(0, photos.count - 1))
        self.words = words
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var current: PhotoPageController? { pages.viewControllers?.first as? PhotoPageController }
    private var mostPanelHeight: CGFloat { view.bounds.height * 0.42 }

    // MARK: - Building

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Theme.background)
        view.accessibilityIdentifier = "photo-viewer"
        buildPages()
        buildPanel()
        buildBar()
        buildGestures()
        if let page = page(at: index) {
            pages.setViewControllers([page], direction: .forward, animated: false)
            became(page)
        }
        panel.text = words
        refreshBar()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if panelShown {
            panelHeight.constant = panel.height(for: view.bounds.width, most: mostPanelHeight)
        }
    }

    private func buildPages() {
        addChild(pages)
        pages.dataSource = self
        pages.delegate = self
        pages.view.translatesAutoresizingMaskIntoConstraints = false
        pages.view.backgroundColor = .clear
        view.addSubview(pages.view)
        pages.didMove(toParent: self)
    }

    private func buildPanel() {
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.alpha = 0
        panel.onChange = { [weak self] in self?.layoutPanel(animated: true) }
        panel.onEnd = { [weak self] text in
            guard let self, text != self.words else { return }
            self.words = text
            self.onWords?(text)
            self.refreshBar()
        }
        view.addSubview(panel)
        panelHeight = panel.heightAnchor.constraint(equalToConstant: 0)
        pagesToTop = pages.view.topAnchor.constraint(equalTo: view.topAnchor)
        pagesBelowBar = pages.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60)
        NSLayoutConstraint.activate([
            pagesToTop,
            pages.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pages.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pages.view.bottomAnchor.constraint(equalTo: panel.topAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Above the keyboard when it is up, above the home indicator when it is not.
            panel.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            panelHeight,
        ])
    }

    private func buildBar() {
        let ground = UIColor(Theme.background).withAlphaComponent(0.85)
        func square(_ button: UIButton, _ symbol: String, _ label: String) {
            var configuration = button.configuration ?? .plain()
            configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
            configuration.baseForegroundColor = UIColor(Theme.foreground)
            configuration.background.backgroundColor = ground
            configuration.background.cornerRadius = 44 * 0.22
            configuration.cornerStyle = .fixed
            button.configuration = configuration
            button.accessibilityLabel = label
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 44), button.heightAnchor.constraint(equalToConstant: 44)])
        }
        square(closeButton, "xmark", "Close")
        square(wordsButton, "text.below.photo", "Words")
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .primaryActionTriggered)
        wordsButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.setPanel(!self.panelShown, animated: true)
        }, for: .primaryActionTriggered)

        var quote = UIButton.Configuration.filled()
        quote.title = "Quote"
        quote.baseBackgroundColor = UIColor(Theme.accent)
        quote.baseForegroundColor = UIColor(Theme.background)
        quote.background.cornerRadius = 36 * 0.22
        quote.cornerStyle = .fixed
        quote.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        quote.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            return attributes
        }
        quoteButton.configuration = quote
        quoteButton.accessibilityLabel = "Quote"
        quoteButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        quoteButton.addAction(UIAction { [weak self] _ in self?.quote() }, for: .primaryActionTriggered)

        for label in [countLabel, pageLabel] {
            label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            label.textColor = UIColor(Theme.muted)
        }
        pageLabel.accessibilityIdentifier = "page-count"

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.axis = .horizontal
        bar.alignment = .center
        bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false
        for item in [pageLabel, quoteButton, countLabel, spacer, wordsButton, closeButton] { bar.addArrangedSubview(item) }
        bar.setCustomSpacing(12, after: countLabel)
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            bar.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func buildGestures() {
        tap.delegate = self
        pull.delegate = self
        pull.maximumNumberOfTouches = 1
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pull)
    }

    // MARK: - From outside

    /// The line as the notebook has it now. Photos that changed rebuild the pages; words that
    /// changed land in the panel unless it is being written in.
    func show(photos: [Photo], words: String) {
        if photos != self.photos {
            self.photos = photos
            index = min(index, max(0, photos.count - 1))
            if let page = page(at: index) {
                pages.setViewControllers([page], direction: .forward, animated: false)
                became(page)
            }
        }
        if words != self.words {
            self.words = words
            if !panel.isEditing { panel.text = words }
            refreshBar()
        }
    }

    // MARK: - Pages

    private func page(at position: Int) -> PhotoPageController? {
        guard photos.indices.contains(position) else { return nil }
        let photo = photos[position]
        let page = PhotoPageController(photo: photo, position: position, image: decoded[photo.hash])
        page.onImage = { [weak self] image in self?.decoded[photo.hash] = image }
        page.onSelection = { [weak self] words in
            guard let self, self.current === page else { return }
            self.selection = words
            self.refreshBar()
        }
        return page
    }

    /// A page is on screen: the single tap waits for its double tap, the counter says where.
    private func became(_ page: PhotoPageController) {
        index = page.position
        tap.require(toFail: page.zoom.doubleTap)
        selection = ""
        refreshBar()
    }

    private func refreshBar() {
        let quoting = !selection.isEmpty
        quoteButton.isHidden = !quoting
        countLabel.isHidden = !quoting
        countLabel.text = wordCount(selection)
        pageLabel.isHidden = quoting || photos.count < 2
        pageLabel.text = "\(index + 1) / \(photos.count)"
        var configuration = wordsButton.configuration
        configuration?.image = UIImage(systemName: words.isEmpty ? "text.below.photo" : "text.below.photo.fill",
                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        configuration?.baseForegroundColor = UIColor(panelShown ? Theme.accent : Theme.foreground)
        wordsButton.configuration = configuration
    }

    // MARK: - The panel

    private func setPanel(_ shown: Bool, animated: Bool) {
        guard shown != panelShown else { return }
        panelShown = shown
        if !shown { panel.endEditing(true) }
        refreshBar()
        layoutPanel(animated: animated)
    }

    private func layoutPanel(animated: Bool) {
        panelHeight.constant = panelShown ? panel.height(for: view.bounds.width, most: mostPanelHeight) : 0
        pagesToTop.isActive = !panelShown
        pagesBelowBar.isActive = panelShown
        let change = {
            self.panel.alpha = self.panelShown ? 1 : 0
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(springDuration: 0.45, bounce: 0, animations: change)
        } else {
            change()
        }
    }

    /// The selected words join the line's, in quotation marks. The words before stay in the
    /// line's history, as with any edit.
    private func quote() {
        let passage = selection.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !passage.isEmpty else { return }
        let quoted = "\u{201C}\(passage)\u{201D}"
        let joined = words.isEmpty ? quoted : "\(words) \(quoted)"
        words = joined
        panel.text = joined
        onWords?(joined)
        current?.clearSelection()
        selection = ""
        refreshBar()
        Haptic.store()
        if !panelShown { setPanel(true, animated: true) }
    }

    // MARK: - Hands

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        // A tap on words in the photo is Live Text's, not ours.
        if let current, current.hasText(at: gesture.location(in: current.view)) { return }
        chromeShown.toggle()
        UIView.animate(withDuration: 0.15) { self.bar.alpha = self.chromeShown ? 1 : 0 }
    }

    @objc private func pulled(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let moved = gesture.translation(in: view).y
        let speed = gesture.velocity(in: view).y
        if moved < -40 || speed < -400 {
            setPanel(true, animated: true)
        } else if moved > 40 || speed > 400 {
            setPanel(false, animated: true)
        }
    }
}

extension PhotoViewerController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? PhotoPageController else { return nil }
        return self.page(at: page.position - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? PhotoPageController else { return nil }
        return self.page(at: page.position + 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let page = current else { return }
        for previous in previousViewControllers { (previous as? PhotoPageController)?.clearSelection() }
        became(page)
    }
}

extension PhotoViewerController: UIGestureRecognizerDelegate {
    /// Our tap and pull belong to the photo area. The bar and the panel have their own hands.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touched = touch.view else { return false }
        return touched.isDescendant(of: pages.view)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pull else { return true }
        guard current?.zoom.zoomed != true else { return false }
        let velocity = pull.velocity(in: view)
        guard abs(velocity.y) > abs(velocity.x) else { return false }
        return panelShown || velocity.y < 0
    }

    /// Whoever listens for a pull outside the photo area, the dismissing transition, waits
    /// until our pull has declined it. The pager's and the zooming view's own hands inside
    /// the photo area are left alone.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pull, let view = other.view else { return false }
        return !view.isDescendant(of: pages.view)
    }
}

/// One photo on one page: the zooming view, the image loading in behind its thumbnail, and
/// Live Text on the image.
final class PhotoPageController: UIViewController, ImageAnalysisInteractionDelegate {
    let photo: PhotoViewerController.Photo
    let position: Int
    let zoom: ZoomingPhotoView
    var onSelection: ((String) -> Void)?
    var onImage: ((UIImage) -> Void)?
    private let interaction = ImageAnalysisInteraction()

    /// What the page shows, in order: the thumbnail while the bytes load, the full photo while
    /// its words are being read, the full photo with its words live. A photo whose bytes could
    /// not be read keeps its thumbnail. Each move forward happens once.
    private enum Picture {
        case loading
        case full(UIImage)
        case read(UIImage)
        case unreadable

        var image: UIImage? {
            switch self {
            case .full(let image), .read(let image): return image
            case .loading, .unreadable: return nil
            }
        }
    }
    private var picture: Picture

    init(photo: PhotoViewerController.Photo, position: Int, image: UIImage?) {
        self.photo = photo
        self.position = position
        self.picture = image.map(Picture.full) ?? .loading
        let aspect = photo.size ?? image?.size ?? photo.thumbnail?.size ?? CGSize(width: 1, height: 1)
        zoom = ZoomingPhotoView(aspect: aspect)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        zoom.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoom)
        NSLayoutConstraint.activate([
            zoom.topAnchor.constraint(equalTo: view.topAnchor),
            zoom.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            zoom.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            zoom.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        zoom.imageView.image = picture.image ?? photo.thumbnail
        zoom.imageView.isAccessibilityElement = true
        zoom.imageView.accessibilityLabel = "Photo"
        zoom.imageView.accessibilityIdentifier = "photo"
        zoom.imageView.accessibilityTraits = .image

        interaction.preferredInteractionTypes = [.textSelection]
        interaction.delegate = self
        zoom.imageView.addInteraction(interaction)

        switch picture {
        case .loading: Task { await load() }
        case .full(let image): Task { await read(image) }
        case .read, .unreadable: break
        }
    }

    /// The bytes come in behind the thumbnail; the full photo takes its place and is read.
    private func load() async {
        guard case .loading = picture else { return }
        guard let image = await Photo.load(photo.url) else {
            picture = .unreadable
            return
        }
        picture = .full(image)
        zoom.imageView.image = image
        onImage?(image)
        await read(image)
    }

    /// Live Text reads the full photo once; its words are live from then on.
    private func read(_ image: UIImage) async {
        guard case .full = picture, ImageAnalyzer.isSupported else { return }
        guard let analysis = await LiveTextView.analysis(of: image) else { return }
        interaction.analysis = analysis
        picture = .read(image)
    }

    func clearSelection() {
        if interaction.hasActiveTextSelection { interaction.resetTextSelection() }
    }

    /// Whether a point on this page lands on words Live Text knows.
    func hasText(at point: CGPoint) -> Bool {
        interaction.hasInteractiveItem(at: view.convert(point, to: zoom.imageView))
    }

    /// Only words start a selection. Everywhere else the touch belongs to the viewer.
    func interaction(_ interaction: ImageAnalysisInteraction, shouldBeginAt point: CGPoint,
                     for interactionType: ImageAnalysisInteraction.InteractionTypes) -> Bool {
        interaction.hasInteractiveItem(at: point) || interaction.hasActiveTextSelection
    }

    func textSelectionDidChange(_ interaction: ImageAnalysisInteraction) {
        onSelection?(interaction.selectedText)
    }
}

/// A scroll view that zooms one image: fitted and centred at rest, pinch around the fingers
/// up to four times, pan to the edges with the rubber band once zoomed, double tap into the
/// spot and back. At rest the content fits and nothing bounces, so a pull is not its to take
/// and reaches the transition behind it.
final class ZoomingPhotoView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    let doubleTap: UITapGestureRecognizer
    private let aspect: CGSize
    private var fittedFor: CGSize = .zero

    var zoomed: Bool { zoomScale > 1.01 }

    init(aspect: CGSize) {
        self.aspect = aspect.width > 0 && aspect.height > 0 ? aspect : CGSize(width: 1, height: 1)
        doubleTap = UITapGestureRecognizer()
        super.init(frame: .zero)
        delegate = self
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        bouncesZoom = true
        alwaysBounceVertical = false
        alwaysBounceHorizontal = false
        maximumZoomScale = 4
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)
        doubleTap.numberOfTapsRequired = 2
        doubleTap.addTarget(self, action: #selector(doubleTapped(_:)))
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedFor {
            fittedFor = bounds.size
            fit()
        } else {
            centre()
        }
    }

    /// The photo at the width or height of the view, whichever it reaches first.
    private func fit() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        zoomScale = 1
        let width = min(bounds.width, bounds.height * aspect.width / aspect.height)
        let fitted = CGSize(width: width, height: width * aspect.height / aspect.width)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
        centre()
    }

    /// Centred while smaller than the view, in either direction.
    private func centre() {
        let dx = max(0, (bounds.width - contentSize.width) / 2)
        let dy = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centre()
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomed {
            setZoomScale(1, animated: true)
        } else {
            let scale: CGFloat = 2.5
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}

/// The line's words below the photo: a hairline, then the words, editable in place. Return
/// ends the edit. As tall as the words up to a cap, scrolling beyond it.
final class WordsPanel: UIView, UITextViewDelegate {
    private let rule = UIView()
    private let textView = UITextView()
    private let placeholder = UILabel()
    private let insets = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
    var onChange: (() -> Void)?
    var onEnd: ((String) -> Void)?

    var text: String {
        get { textView.text ?? "" }
        set {
            guard textView.text != newValue else { return }
            textView.attributedText = NSAttributedString(string: newValue, attributes: attributes)
            placeholder.isHidden = !newValue.isEmpty
        }
    }

    var isEditing: Bool { textView.isFirstResponder }

    private var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        return [.font: UIFont.serif(18, scaled: true), .foregroundColor: UIColor(Theme.foreground), .paragraphStyle: paragraph]
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = UIColor(Theme.background)
        rule.backgroundColor = UIColor(Theme.line)
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rule)
        textView.delegate = self
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = false
        textView.showsVerticalScrollIndicator = false
        textView.returnKeyType = .done
        textView.autocapitalizationType = .sentences
        textView.adjustsFontForContentSizeCategory = true
        textView.typingAttributes = attributes
        textView.accessibilityIdentifier = "words"
        textView.accessibilityLabel = "Words for this"
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        placeholder.text = "Words for this"
        placeholder.font = .serif(18, scaled: true)
        placeholder.textColor = UIColor(Theme.faint)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.isUserInteractionEnabled = false
        addSubview(placeholder)
        NSLayoutConstraint.activate([
            rule.topAnchor.constraint(equalTo: topAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
            textView.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor),
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// As tall as the words at this width, and no taller than `most`; past that the words scroll.
    func height(for width: CGFloat, most: CGFloat) -> CGFloat {
        let room = width - insets.left - insets.right
        guard room > 0 else { return 0 }
        let words = textView.sizeThatFits(CGSize(width: room, height: .greatestFiniteMagnitude)).height
        let line = UIFont.serif(18, scaled: true).lineHeight
        let wanted = max(words, line) + insets.top + insets.bottom
        textView.isScrollEnabled = wanted > most
        return min(wanted, most).rounded(.up)
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholder.isHidden = !(textView.text ?? "").isEmpty
        onChange?()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        }
        // A pasted passage keeps its words and loses its breaks, as everywhere else.
        guard text.rangeOfCharacter(from: .newlines) != nil else { return true }
        let flat = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        textView.textStorage.replaceCharacters(in: range, with: NSAttributedString(string: flat, attributes: attributes))
        textView.selectedRange = NSRange(location: range.location + (flat as NSString).length, length: 0)
        textViewDidChange(textView)
        return false
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        onEnd?((textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
