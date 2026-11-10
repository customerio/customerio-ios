import CioAnalytics

extension DataPipelineImplementation {
    /// Keeps `push_enabled` current when the user changes notification permission while the app runs.
    func startPushEnabledRefresh() {
        guard moduleConfig.autoTrackDeviceAttributes else { return }

        // didBecomeActive, as answering the in-app permission alert returns to the app without entering the foreground
        contextPlugin.onBecameActive.wrappedValue = { [weak self] in
            self?.refreshPushEnabledIfChanged()
        }
    }

    /// Sends a device update when `push_enabled` differs from the value this process last sent.
    /// Skipped while no profile is identified, and until a device update is sent, including after the device is deleted.
    func refreshPushEnabledIfChanged() {
        guard registeredUserId != nil, registeredDeviceToken != nil else { return }

        deviceInfo.isPushSubscribed { [weak self] isEnabled in
            guard let self else { return }

            // Held through sending, as in token registration, so a token registered meanwhile isn't replaced by this one
            self.deviceTokenLock.lock()
            defer { self.deviceTokenLock.unlock() }

            let pushEnabled = String(isEnabled)
            // Checked again, as the profile can be cleared while the permission is read
            guard self.registeredUserId != nil,
                  let token = self.registeredDeviceToken,
                  let lastSent = self.contextPlugin.attributes[DeviceAttributeKey.pushEnabled] as? String,
                  lastSent != pushEnabled
            else { return }

            // Recorded before sending, so checks running at the same time send once
            self.contextPlugin.attributes[DeviceAttributeKey.pushEnabled] = pushEnabled
            self.addDeviceAttributes(token: token)
        }
    }

    /// Stops the refresh until the next device update, so it doesn't re-create a deleted device.
    func forgetSentPushEnabled() {
        deviceTokenLock.lock()
        defer { deviceTokenLock.unlock() }

        contextPlugin.attributes[DeviceAttributeKey.pushEnabled] = nil
    }
}
