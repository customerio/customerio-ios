import UIKit

class ThemeButton: UIButton {
    // Default colors
    var defaultBackgroundColor = UIColor(red: 60.0 / 255, green: 67.0 / 255, blue: 125.0 / 255, alpha: 1.0)
    var defaultTitleColor: UIColor = .white

    // Highlight color
    var highlightTitleColor: UIColor = .white.withAlphaComponent(0.7)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func setup() {
        layer.cornerRadius = 5
        frame.size.height = 50

        // Set default state colors
        setTitleColor(defaultTitleColor, for: .normal)
        setTitleColor(highlightTitleColor, for: .highlighted)
        setTitleColor(highlightTitleColor, for: [.highlighted, .selected])

        // Set background color for normal state
        backgroundColor = defaultBackgroundColor
    }
}
