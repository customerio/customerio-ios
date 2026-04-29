extension CIOKeys {

    /// Storage table names and keys that are referenced by more than one module.
    ///
    /// Keys that belong entirely within a single module (e.g. `IdentityStore`'s
    /// `"anonymous_id"`) stay in that module's own `CIOKeys` extension.
    public enum Storage {

        // MARK: - Table names

        /// The `device` table — stores per-installation attributes including the push token.
        ///
        /// Shared between `CustomerIO.DeviceStore` and `MessagingPush.StorageManager+Push`.
        public static let deviceTable = "device"

        // MARK: - Keys

        /// Storage key for the device push token inside the `device` table.
        ///
        /// Shared between `CustomerIO.DeviceStore` and `MessagingPush.StorageManager+Push`.
        public static let pushTokenKey = "push_token"

        /// `sdk_meta` key that records whether the one-time legacy migration has run.
        public static let legacyMigrationCompleteKey = "legacy_migration_complete"
    }
}
