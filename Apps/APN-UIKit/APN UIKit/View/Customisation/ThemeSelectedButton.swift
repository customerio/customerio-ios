import UIKit

class ThemeSelectedButton: UIButton {
    // Default colors
    private static var primaryColor = UIColor(red: 60.0 / 255, green: 67.0 / 255, blue: 125.0 / 255, alpha: 1.0)
    private static var primaryTextColor: UIColor = .white

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Improve styling
        layer.cornerRadius = 12
        clipsToBounds = false

        // Apply shadows
        applyShadow()

        // Typography
        titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel?.textAlignment = .center

        // Configure initial appearance
        configureAppearance(
            backgroundColor: Self.primaryColor.withAlphaComponent(0.1),
            titleColor: Self.primaryColor,
            borderColor: Self.primaryColor.withAlphaComponent(0.3)
        )

        // Add touch animations
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    private func configureAppearance(backgroundColor: UIColor, titleColor: UIColor, borderColor: UIColor) {
        self.backgroundColor = backgroundColor
        setTitleColor(titleColor, for: .normal)
        layer.borderWidth = 1.5
        layer.borderColor = borderColor.cgColor
    }

    override var isSelected: Bool {
        didSet {
            updateAppearance()
        }
    }

    private func updateAppearance() {
        // Set text colors immediately to avoid readability issues
        setTitleColors(isSelected ? Self.primaryTextColor : Self.primaryColor)

        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut], animations: {
            if self.isSelected {
                self.backgroundColor = Self.primaryColor
                self.layer.borderColor = Self.primaryColor.cgColor
                self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            } else {
                self.backgroundColor = Self.primaryColor.withAlphaComponent(0.1)
                self.layer.borderColor = Self.primaryColor.withAlphaComponent(0.3).cgColor
                self.transform = .identity
            }
        })
    }

    private func setTitleColors(_ color: UIColor) {
        setTitleColor(color, for: .normal)
        setTitleColor(color, for: .selected)
        setTitleColor(color, for: .highlighted)
        tintColor = color
    }

    private func applyShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.15
    }

    @objc private func touchDown() {
        UIView.animate(withDuration: 0.1) {
            self.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            self.alpha = 0.8
        }
    }

    @objc private func touchUp() {
        UIView.animate(withDuration: 0.1) {
            // Let updateAppearance() handle transform animation, just restore alpha
            self.alpha = 1.0
        }
    }
}
