/// Root namespace for SDK string constants.
///
/// Each module extends this type with its own domain-specific constants:
///
///     // In MyModule:
///     extension CIOKeys {
///         enum MyModule {
///             static let someStorageKey = "my_key"
///         }
///     }
///
/// Constants shared between multiple modules live here in `CustomerIO_Utilities`
/// so every target that imports the utilities layer can use them.
public enum CIOKeys {}
