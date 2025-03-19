import UIKit

class ThemeSelectedButton: UIButton {
    // Default colors
    var defaultBackgroundColor = UIColor(red: 60.0 / 255, green: 67.0 / 255, blue: 125.0 / 255, alpha: 0.7)
    var defaultTitleColor: UIColor = .white

    // Selected colors
    var selectedBackgroundColor = UIColor(red: 60.0 / 255, green: 67.0 / 255, blue: 125.0 / 255, alpha: 1.0)

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

        // Added to prevent automatic tinging for selected state
        tintColor = .clear

        // Configure colors for all states
        setTitleColor(defaultTitleColor, for: .normal)
        setTitleColor(defaultTitleColor, for: .selected)
        setTitleColor(highlightTitleColor, for: .highlighted)
        setTitleColor(highlightTitleColor, for: [.highlighted, .selected])

        // Set background color for normal state
        backgroundColor = defaultBackgroundColor
    }

    override var isSelected: Bool {
        didSet {
            backgroundColor = isSelected ? selectedBackgroundColor : defaultBackgroundColor
            setBackgroundImage(nil, for: .normal)
            setBackgroundImage(nil, for: .selected)
        }
    }
}
