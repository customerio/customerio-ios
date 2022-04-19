## [1.1.0-beta.1](https://github.com/customerio/customerio-ios/compare/1.0.3...1.1.0-beta.1) (2022-04-19)


### Features

* add device_manufacturer device attribute ([585aefb](https://github.com/customerio/customerio-ios/commit/585aefbad99a06ac54c8358ffac89d3a5beba857))
* adding support for device attributes and custom device attributes ([#143](https://github.com/customerio/customerio-ios/issues/143)) ([84ead00](https://github.com/customerio/customerio-ios/commit/84ead00911416b39a25a2318c6e9a084bde22c75))


### Bug Fixes

* add siteid to logs help with multi-workspace ([#130](https://github.com/customerio/customerio-ios/issues/130)) ([0ad3906](https://github.com/customerio/customerio-ios/commit/0ad39061e5add7f69e9617056a99669b00814df9))
* change property name from push_subscribed to push_enabled ([2f071ec](https://github.com/customerio/customerio-ios/commit/2f071ec2d48465731cfbb17c051d8f16a5cbb10c))
* locale uses preferred language ([4a5ecf1](https://github.com/customerio/customerio-ios/commit/4a5ecf149cf43d5b0df3b0f01ef24063c1f3a6c8))
* missing public sdk functions ([0ca0618](https://github.com/customerio/customerio-ios/commit/0ca06183f9c0094019e3e58d0963b5931909c348))
* remove platform from os_version attribute ([f735197](https://github.com/customerio/customerio-ios/commit/f7351973d1a0edf47952133fa6b62bfe06a3e5a1))
* use dashes instead of underscores device locale ([f85e858](https://github.com/customerio/customerio-ios/commit/f85e858d673fa24da324e0feecb4678c241c907e))

## [1.1.0-alpha.3](https://github.com/customerio/customerio-ios/compare/1.1.0-alpha.2...1.1.0-alpha.3) (2022-04-19)


### Features

* add device_manufacturer device attribute ([585aefb](https://github.com/customerio/customerio-ios/commit/585aefbad99a06ac54c8358ffac89d3a5beba857))


### Bug Fixes

* locale uses preferred language ([4a5ecf1](https://github.com/customerio/customerio-ios/commit/4a5ecf149cf43d5b0df3b0f01ef24063c1f3a6c8))

## [1.1.0-alpha.2](https://github.com/customerio/customerio-ios/compare/1.1.0-alpha.1...1.1.0-alpha.2) (2022-03-25)


### Bug Fixes

* remove platform from os_version attribute ([f735197](https://github.com/customerio/customerio-ios/commit/f7351973d1a0edf47952133fa6b62bfe06a3e5a1))
* use dashes instead of underscores device locale ([f85e858](https://github.com/customerio/customerio-ios/commit/f85e858d673fa24da324e0feecb4678c241c907e))

## [1.1.0-alpha.1](https://github.com/customerio/customerio-ios/compare/1.0.3...1.1.0-alpha.1) (2022-03-22)


### Features

* adding support for device attributes and custom device attributes ([#143](https://github.com/customerio/customerio-ios/issues/143)) ([84ead00](https://github.com/customerio/customerio-ios/commit/84ead00911416b39a25a2318c6e9a084bde22c75))


### Bug Fixes

* add siteid to logs help with multi-workspace ([#130](https://github.com/customerio/customerio-ios/issues/130)) ([0ad3906](https://github.com/customerio/customerio-ios/commit/0ad39061e5add7f69e9617056a99669b00814df9))
* change property name from push_subscribed to push_enabled ([2f071ec](https://github.com/customerio/customerio-ios/commit/2f071ec2d48465731cfbb17c051d8f16a5cbb10c))
* missing public sdk functions ([0ca0618](https://github.com/customerio/customerio-ios/commit/0ca06183f9c0094019e3e58d0963b5931909c348))

## [1.0.3](https://github.com/customerio/customerio-ios/compare/1.0.2...1.0.3) (2022-03-15)


### Bug Fixes

* delete device token from profile on logout ([#145](https://github.com/customerio/customerio-ios/issues/145)) ([d976c27](https://github.com/customerio/customerio-ios/commit/d976c27b3200f124260c3d006f825613cb308b12))

## [1.0.2](https://github.com/customerio/customerio-ios/compare/1.0.1...1.0.2) (2022-02-07)


### Bug Fixes

* create valid JSON request body when sending nil as track events data ([#140](https://github.com/customerio/customerio-ios/issues/140)) ([c5d1a50](https://github.com/customerio/customerio-ios/commit/c5d1a50b46422257d4cd770ff052d5d9e6daee38))

## [1.0.1](https://github.com/customerio/customerio-ios/compare/1.0.0...1.0.1) (2022-02-02)


### Bug Fixes

* data:null as HTTP request body ([#135](https://github.com/customerio/customerio-ios/issues/135)) ([04c5211](https://github.com/customerio/customerio-ios/commit/04c5211ac83592e7191d7313a61e37cea8be38fa))

# 1.0.0 (2022-01-19)


### Bug Fixes

* add createdAt timestamp to added queue tasks  ([#106](https://github.com/customerio/customerio-ios/issues/106)) ([46aab62](https://github.com/customerio/customerio-ios/commit/46aab6212093ef374df7952f5c335e166a26498e))
* automatic screenview tracking correct siteid ([#120](https://github.com/customerio/customerio-ios/issues/120)) ([abd3ea9](https://github.com/customerio/customerio-ios/commit/abd3ea9fdf3b68bd85aa88e4e89d972182c1a3d9))
* background queue timer scheduling and running ([#114](https://github.com/customerio/customerio-ios/issues/114)) ([6be8a74](https://github.com/customerio/customerio-ios/commit/6be8a7404c5bee1d201138b20dc1abd017254546))
* call callback on main thread APN tokens ([#40](https://github.com/customerio/customerio-ios/issues/40)) ([982ce9d](https://github.com/customerio/customerio-ios/commit/982ce9d9a8277d72d3fa49c66537a0a6f5b6401a))
* change hostname for CIO API ([#109](https://github.com/customerio/customerio-ios/issues/109)) ([90e9407](https://github.com/customerio/customerio-ios/commit/90e9407ceb0c1f6f59c7ad7c835ac556651f55ef))
* convert APN device token to string ([#39](https://github.com/customerio/customerio-ios/issues/39)) ([1f64a13](https://github.com/customerio/customerio-ios/commit/1f64a13467966f077642745d9f60a168113bdbff))
* deep links previously being ignored ([#79](https://github.com/customerio/customerio-ios/issues/79)) ([2041767](https://github.com/customerio/customerio-ios/commit/204176735a8641a77d58232af1daa4e290ee0ca4))
* duplicate entries for active workspace ([#124](https://github.com/customerio/customerio-ios/issues/124)) ([c903e4a](https://github.com/customerio/customerio-ios/commit/c903e4a972bc8d1ea7ecbbd013b4fd5dfef6ddc2))
* improve user-agent with more detail ([#74](https://github.com/customerio/customerio-ios/issues/74)) ([4301034](https://github.com/customerio/customerio-ios/commit/43010347680d84dfa7d2b782bce18a25b40b8296))
* logs now show up in mac console app ([#80](https://github.com/customerio/customerio-ios/issues/80)) ([535d0be](https://github.com/customerio/customerio-ios/commit/535d0be1bdbd3a43d9ba1fe2fabeb4002ea5d35f))
* more safely handle 5xx, 401 status codes ([#107](https://github.com/customerio/customerio-ios/issues/107)) ([d56807b](https://github.com/customerio/customerio-ios/commit/d56807bdbda95e11d742916db4b19e545bead6d7))
* mutex locks shared across instances ([#119](https://github.com/customerio/customerio-ios/issues/119)) ([cb169bf](https://github.com/customerio/customerio-ios/commit/cb169bf71acd5c0fff9b971894465800b4a7bfbc))
* opened push metrics ([#70](https://github.com/customerio/customerio-ios/issues/70)) ([a277378](https://github.com/customerio/customerio-ios/commit/a2773782811b581d17cc2eb554c321d91c8b6b67))
* opened push metrics being sent to API again ([#111](https://github.com/customerio/customerio-ios/issues/111)) ([93971bf](https://github.com/customerio/customerio-ios/commit/93971bf8e8bf272fbcc73d327069ce0cd244066d))
* remove apn device token profile request body ([#41](https://github.com/customerio/customerio-ios/issues/41)) ([61946c4](https://github.com/customerio/customerio-ios/commit/61946c4dea617561891188aa537277cc67af35ae))
* remove custom jsonencoder public functions ([#122](https://github.com/customerio/customerio-ios/issues/122)) ([061a568](https://github.com/customerio/customerio-ios/commit/061a5684a170bd231d5583d56b32406f0086a456))
* rename singletons instance to shared ([#34](https://github.com/customerio/customerio-ios/issues/34)) ([3bf1384](https://github.com/customerio/customerio-ios/commit/3bf1384ce9b2d4a8551bb353c1b0e6ce195378df))
* rename stop identify function ([#31](https://github.com/customerio/customerio-ios/issues/31)) ([d97e931](https://github.com/customerio/customerio-ios/commit/d97e931fa7a001e7a58658471244dcfc1494a386))
* screen view tracking ([#108](https://github.com/customerio/customerio-ios/issues/108)) ([f836b9a](https://github.com/customerio/customerio-ios/commit/f836b9aaa59cd525afc4db935db4b378f71fa8f4))
* track events type in HTTP requests ([#117](https://github.com/customerio/customerio-ios/issues/117)) ([745d4ad](https://github.com/customerio/customerio-ios/commit/745d4ad642be84f27688b45e2608db1c44cf2798))


### Features

* add [String:Any] support to identify & track ([#94](https://github.com/customerio/customerio-ios/issues/94)) ([5a220c4](https://github.com/customerio/customerio-ios/commit/5a220c401c1df1153cdb0cb56efe5a885dd08c68))
* add screen view tracking ([#82](https://github.com/customerio/customerio-ios/issues/82)) ([c2034a6](https://github.com/customerio/customerio-ios/commit/c2034a6fcbcea15716529a4091538f5bb8dc6a00))
* automatic push events ([#63](https://github.com/customerio/customerio-ios/issues/63)) ([cf81b23](https://github.com/customerio/customerio-ios/commit/cf81b2381993d7108ee7b860d4221c929a98d5d7))
* create background queue  ([#99](https://github.com/customerio/customerio-ios/issues/99)) ([80fffb8](https://github.com/customerio/customerio-ios/commit/80fffb881f69337125b189fbf4de5c47bd6c22f2))
* create mocks for push messaging ([#35](https://github.com/customerio/customerio-ios/issues/35)) ([b2c5d62](https://github.com/customerio/customerio-ios/commit/b2c5d6221434e9c559bf818790c48d31decf7f77))
* event tracking ([#42](https://github.com/customerio/customerio-ios/issues/42)) ([be768bb](https://github.com/customerio/customerio-ios/commit/be768bbb32680ac0ca8dce098f62720394965f85))
* identify customer ([#27](https://github.com/customerio/customerio-ios/issues/27)) ([f79d1c9](https://github.com/customerio/customerio-ios/commit/f79d1c9737f215beef4b69167db31ac0d51a16dd))
* make US default region ([#28](https://github.com/customerio/customerio-ios/issues/28)) ([1d10a8f](https://github.com/customerio/customerio-ios/commit/1d10a8ffc773bf82f0b20abde09fbb95b01797e5))
* register device token with FCM ([#46](https://github.com/customerio/customerio-ios/issues/46)) ([f6a87e0](https://github.com/customerio/customerio-ios/commit/f6a87e0e889b9fdac2c8093a8f4fb4f5f0e9ea2a))
* register/delete device tokens ([#26](https://github.com/customerio/customerio-ios/issues/26)) ([d0ddc07](https://github.com/customerio/customerio-ios/commit/d0ddc07c6b2c25e1168be47e61821e78f5c158a5))
* rich push deep links ([#45](https://github.com/customerio/customerio-ios/issues/45)) ([fe21cc8](https://github.com/customerio/customerio-ios/commit/fe21cc87e7146c01df96fbda858e7bd69a6851cb))
* rich push images ([#59](https://github.com/customerio/customerio-ios/issues/59)) ([03fc284](https://github.com/customerio/customerio-ios/commit/03fc284f09bb79db53dbc42d78c39acd1204843e))
* save all siteids registered with SDK ([#30](https://github.com/customerio/customerio-ios/issues/30)) ([95db6dc](https://github.com/customerio/customerio-ios/commit/95db6dc9462a892f8c46d083be85a97dde1e0b76))
* subsequent identifies without passing identifier ([#96](https://github.com/customerio/customerio-ios/issues/96)) ([47d9166](https://github.com/customerio/customerio-ios/commit/47d916634a5ab34842a19074f3b3c110de4e0348))
* track push events ([#47](https://github.com/customerio/customerio-ios/issues/47)) ([a37e60e](https://github.com/customerio/customerio-ios/commit/a37e60ef390e8cb9c4693c08ae21221186fe8dd2))

# [1.0.0-beta.3](https://github.com/customerio/customerio-ios/compare/1.0.0-beta.2...1.0.0-beta.3) (2022-01-19)


### Bug Fixes

* duplicate entries for active workspace ([#124](https://github.com/customerio/customerio-ios/issues/124)) ([c903e4a](https://github.com/customerio/customerio-ios/commit/c903e4a972bc8d1ea7ecbbd013b4fd5dfef6ddc2))

# [1.0.0-beta.2](https://github.com/customerio/customerio-ios/compare/1.0.0-beta.1...1.0.0-beta.2) (2022-01-19)


### Bug Fixes

* add createdAt timestamp to added queue tasks  ([#106](https://github.com/customerio/customerio-ios/issues/106)) ([46aab62](https://github.com/customerio/customerio-ios/commit/46aab6212093ef374df7952f5c335e166a26498e))
* automatic screenview tracking correct siteid ([#120](https://github.com/customerio/customerio-ios/issues/120)) ([abd3ea9](https://github.com/customerio/customerio-ios/commit/abd3ea9fdf3b68bd85aa88e4e89d972182c1a3d9))
* background queue timer scheduling and running ([#114](https://github.com/customerio/customerio-ios/issues/114)) ([6be8a74](https://github.com/customerio/customerio-ios/commit/6be8a7404c5bee1d201138b20dc1abd017254546))
* change hostname for CIO API ([#109](https://github.com/customerio/customerio-ios/issues/109)) ([90e9407](https://github.com/customerio/customerio-ios/commit/90e9407ceb0c1f6f59c7ad7c835ac556651f55ef))
* more safely handle 5xx, 401 status codes ([#107](https://github.com/customerio/customerio-ios/issues/107)) ([d56807b](https://github.com/customerio/customerio-ios/commit/d56807bdbda95e11d742916db4b19e545bead6d7))
* mutex locks shared across instances ([#119](https://github.com/customerio/customerio-ios/issues/119)) ([cb169bf](https://github.com/customerio/customerio-ios/commit/cb169bf71acd5c0fff9b971894465800b4a7bfbc))
* opened push metrics being sent to API again ([#111](https://github.com/customerio/customerio-ios/issues/111)) ([93971bf](https://github.com/customerio/customerio-ios/commit/93971bf8e8bf272fbcc73d327069ce0cd244066d))
* remove custom jsonencoder public functions ([#122](https://github.com/customerio/customerio-ios/issues/122)) ([061a568](https://github.com/customerio/customerio-ios/commit/061a5684a170bd231d5583d56b32406f0086a456))
* screen view tracking ([#108](https://github.com/customerio/customerio-ios/issues/108)) ([f836b9a](https://github.com/customerio/customerio-ios/commit/f836b9aaa59cd525afc4db935db4b378f71fa8f4))
* track events type in HTTP requests ([#117](https://github.com/customerio/customerio-ios/issues/117)) ([745d4ad](https://github.com/customerio/customerio-ios/commit/745d4ad642be84f27688b45e2608db1c44cf2798))


### Features

* add [String:Any] support to identify & track ([#94](https://github.com/customerio/customerio-ios/issues/94)) ([5a220c4](https://github.com/customerio/customerio-ios/commit/5a220c401c1df1153cdb0cb56efe5a885dd08c68))
* add screen view tracking ([#82](https://github.com/customerio/customerio-ios/issues/82)) ([c2034a6](https://github.com/customerio/customerio-ios/commit/c2034a6fcbcea15716529a4091538f5bb8dc6a00))
* create background queue  ([#99](https://github.com/customerio/customerio-ios/issues/99)) ([80fffb8](https://github.com/customerio/customerio-ios/commit/80fffb881f69337125b189fbf4de5c47bd6c22f2))
* subsequent identifies without passing identifier ([#96](https://github.com/customerio/customerio-ios/issues/96)) ([47d9166](https://github.com/customerio/customerio-ios/commit/47d916634a5ab34842a19074f3b3c110de4e0348))

# [1.0.0-alpha.33](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.32...1.0.0-alpha.33) (2022-01-19)


### Bug Fixes

* more safely handle 5xx, 401 status codes ([#107](https://github.com/customerio/customerio-ios/issues/107)) ([d56807b](https://github.com/customerio/customerio-ios/commit/d56807bdbda95e11d742916db4b19e545bead6d7))

# [1.0.0-alpha.32](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.31...1.0.0-alpha.32) (2022-01-19)


### Bug Fixes

* automatic screenview tracking correct siteid ([#120](https://github.com/customerio/customerio-ios/issues/120)) ([abd3ea9](https://github.com/customerio/customerio-ios/commit/abd3ea9fdf3b68bd85aa88e4e89d972182c1a3d9))

# [1.0.0-alpha.31](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.30...1.0.0-alpha.31) (2022-01-19)


### Bug Fixes

* background queue timer scheduling and running ([#114](https://github.com/customerio/customerio-ios/issues/114)) ([6be8a74](https://github.com/customerio/customerio-ios/commit/6be8a7404c5bee1d201138b20dc1abd017254546))

# [1.0.0-alpha.30](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.29...1.0.0-alpha.30) (2022-01-18)


### Bug Fixes

* remove custom jsonencoder public functions ([#122](https://github.com/customerio/customerio-ios/issues/122)) ([061a568](https://github.com/customerio/customerio-ios/commit/061a5684a170bd231d5583d56b32406f0086a456))

# [1.0.0-alpha.29](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.28...1.0.0-alpha.29) (2022-01-18)


### Bug Fixes

* mutex locks shared across instances ([#119](https://github.com/customerio/customerio-ios/issues/119)) ([cb169bf](https://github.com/customerio/customerio-ios/commit/cb169bf71acd5c0fff9b971894465800b4a7bfbc))

# [1.0.0-alpha.28](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.27...1.0.0-alpha.28) (2022-01-14)


### Bug Fixes

* track events type in HTTP requests ([#117](https://github.com/customerio/customerio-ios/issues/117)) ([745d4ad](https://github.com/customerio/customerio-ios/commit/745d4ad642be84f27688b45e2608db1c44cf2798))

# [1.0.0-alpha.27](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.26...1.0.0-alpha.27) (2022-01-14)


### Bug Fixes

* screen view tracking ([#108](https://github.com/customerio/customerio-ios/issues/108)) ([f836b9a](https://github.com/customerio/customerio-ios/commit/f836b9aaa59cd525afc4db935db4b378f71fa8f4))

# [1.0.0-alpha.26](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.25...1.0.0-alpha.26) (2022-01-13)


### Bug Fixes

* opened push metrics being sent to API again ([#111](https://github.com/customerio/customerio-ios/issues/111)) ([93971bf](https://github.com/customerio/customerio-ios/commit/93971bf8e8bf272fbcc73d327069ce0cd244066d))

# [1.0.0-alpha.25](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.24...1.0.0-alpha.25) (2022-01-11)


### Bug Fixes

* change hostname for CIO API ([#109](https://github.com/customerio/customerio-ios/issues/109)) ([90e9407](https://github.com/customerio/customerio-ios/commit/90e9407ceb0c1f6f59c7ad7c835ac556651f55ef))

# [1.0.0-alpha.24](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.23...1.0.0-alpha.24) (2022-01-10)


### Bug Fixes

* add createdAt timestamp to added queue tasks  ([#106](https://github.com/customerio/customerio-ios/issues/106)) ([46aab62](https://github.com/customerio/customerio-ios/commit/46aab6212093ef374df7952f5c335e166a26498e))

# [1.0.0-alpha.23](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.22...1.0.0-alpha.23) (2021-12-17)


### Features

* create background queue  ([#99](https://github.com/customerio/customerio-ios/issues/99)) ([80fffb8](https://github.com/customerio/customerio-ios/commit/80fffb881f69337125b189fbf4de5c47bd6c22f2))

# [1.0.0-alpha.22](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.21...1.0.0-alpha.22) (2021-12-16)


### Features

* subsequent identifies without passing identifier ([#96](https://github.com/customerio/customerio-ios/issues/96)) ([47d9166](https://github.com/customerio/customerio-ios/commit/47d916634a5ab34842a19074f3b3c110de4e0348))

# [1.0.0-alpha.21](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.20...1.0.0-alpha.21) (2021-12-13)


### Features

* add [String:Any] support to identify & track ([#94](https://github.com/customerio/customerio-ios/issues/94)) ([5a220c4](https://github.com/customerio/customerio-ios/commit/5a220c401c1df1153cdb0cb56efe5a885dd08c68))

# [1.0.0-alpha.20](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.19...1.0.0-alpha.20) (2021-12-13)


### Features

* add screen view tracking ([#82](https://github.com/customerio/customerio-ios/issues/82)) ([c2034a6](https://github.com/customerio/customerio-ios/commit/c2034a6fcbcea15716529a4091538f5bb8dc6a00))

# [1.0.0-alpha.19](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.18...1.0.0-alpha.19) (2021-12-03)


### Bug Fixes

* logs now show up in mac console app ([#80](https://github.com/customerio/customerio-ios/issues/80)) ([535d0be](https://github.com/customerio/customerio-ios/commit/535d0be1bdbd3a43d9ba1fe2fabeb4002ea5d35f))

# 1.0.0-beta.1 (2021-12-15)


### Bug Fixes

* call callback on main thread APN tokens ([#40](https://github.com/customerio/customerio-ios/issues/40)) ([982ce9d](https://github.com/customerio/customerio-ios/commit/982ce9d9a8277d72d3fa49c66537a0a6f5b6401a))
* convert APN device token to string ([#39](https://github.com/customerio/customerio-ios/issues/39)) ([1f64a13](https://github.com/customerio/customerio-ios/commit/1f64a13467966f077642745d9f60a168113bdbff))
* deep links previously being ignored ([#79](https://github.com/customerio/customerio-ios/issues/79)) ([2041767](https://github.com/customerio/customerio-ios/commit/204176735a8641a77d58232af1daa4e290ee0ca4))
* improve user-agent with more detail ([#74](https://github.com/customerio/customerio-ios/issues/74)) ([4301034](https://github.com/customerio/customerio-ios/commit/43010347680d84dfa7d2b782bce18a25b40b8296))
* logs now show up in mac console app ([#80](https://github.com/customerio/customerio-ios/issues/80)) ([535d0be](https://github.com/customerio/customerio-ios/commit/535d0be1bdbd3a43d9ba1fe2fabeb4002ea5d35f))
* opened push metrics ([#70](https://github.com/customerio/customerio-ios/issues/70)) ([a277378](https://github.com/customerio/customerio-ios/commit/a2773782811b581d17cc2eb554c321d91c8b6b67))
* remove apn device token profile request body ([#41](https://github.com/customerio/customerio-ios/issues/41)) ([61946c4](https://github.com/customerio/customerio-ios/commit/61946c4dea617561891188aa537277cc67af35ae))
* rename singletons instance to shared ([#34](https://github.com/customerio/customerio-ios/issues/34)) ([3bf1384](https://github.com/customerio/customerio-ios/commit/3bf1384ce9b2d4a8551bb353c1b0e6ce195378df))
* rename stop identify function ([#31](https://github.com/customerio/customerio-ios/issues/31)) ([d97e931](https://github.com/customerio/customerio-ios/commit/d97e931fa7a001e7a58658471244dcfc1494a386))


### Features

* automatic push events ([#63](https://github.com/customerio/customerio-ios/issues/63)) ([cf81b23](https://github.com/customerio/customerio-ios/commit/cf81b2381993d7108ee7b860d4221c929a98d5d7))
* create mocks for push messaging ([#35](https://github.com/customerio/customerio-ios/issues/35)) ([b2c5d62](https://github.com/customerio/customerio-ios/commit/b2c5d6221434e9c559bf818790c48d31decf7f77))
* event tracking ([#42](https://github.com/customerio/customerio-ios/issues/42)) ([be768bb](https://github.com/customerio/customerio-ios/commit/be768bbb32680ac0ca8dce098f62720394965f85))
* identify customer ([#27](https://github.com/customerio/customerio-ios/issues/27)) ([f79d1c9](https://github.com/customerio/customerio-ios/commit/f79d1c9737f215beef4b69167db31ac0d51a16dd))
* make US default region ([#28](https://github.com/customerio/customerio-ios/issues/28)) ([1d10a8f](https://github.com/customerio/customerio-ios/commit/1d10a8ffc773bf82f0b20abde09fbb95b01797e5))
* register device token with FCM ([#46](https://github.com/customerio/customerio-ios/issues/46)) ([f6a87e0](https://github.com/customerio/customerio-ios/commit/f6a87e0e889b9fdac2c8093a8f4fb4f5f0e9ea2a))
* register/delete device tokens ([#26](https://github.com/customerio/customerio-ios/issues/26)) ([d0ddc07](https://github.com/customerio/customerio-ios/commit/d0ddc07c6b2c25e1168be47e61821e78f5c158a5))
* rich push deep links ([#45](https://github.com/customerio/customerio-ios/issues/45)) ([fe21cc8](https://github.com/customerio/customerio-ios/commit/fe21cc87e7146c01df96fbda858e7bd69a6851cb))
* rich push images ([#59](https://github.com/customerio/customerio-ios/issues/59)) ([03fc284](https://github.com/customerio/customerio-ios/commit/03fc284f09bb79db53dbc42d78c39acd1204843e))
* save all siteids registered with SDK ([#30](https://github.com/customerio/customerio-ios/issues/30)) ([95db6dc](https://github.com/customerio/customerio-ios/commit/95db6dc9462a892f8c46d083be85a97dde1e0b76))
* track push events ([#47](https://github.com/customerio/customerio-ios/issues/47)) ([a37e60e](https://github.com/customerio/customerio-ios/commit/a37e60ef390e8cb9c4693c08ae21221186fe8dd2))

# [1.0.0-alpha.18](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.17...1.0.0-alpha.18) (2021-11-18)


### Bug Fixes

* deep links previously being ignored ([#79](https://github.com/customerio/customerio-ios/issues/79)) ([2041767](https://github.com/customerio/customerio-ios/commit/204176735a8641a77d58232af1daa4e290ee0ca4))

# [1.0.0-alpha.17](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.16...1.0.0-alpha.17) (2021-11-03)


### Bug Fixes

* improve user-agent with more detail ([#74](https://github.com/customerio/customerio-ios/issues/74)) ([4301034](https://github.com/customerio/customerio-ios/commit/43010347680d84dfa7d2b782bce18a25b40b8296))

# [1.0.0-alpha.16](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.15...1.0.0-alpha.16) (2021-10-08)


### Bug Fixes

* opened push metrics ([#70](https://github.com/customerio/customerio-ios/issues/70)) ([a277378](https://github.com/customerio/customerio-ios/commit/a2773782811b581d17cc2eb554c321d91c8b6b67))

# [1.0.0-alpha.15](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.14...1.0.0-alpha.15) (2021-09-25)


### Features

* automatic push events ([#63](https://github.com/customerio/customerio-ios/issues/63)) ([cf81b23](https://github.com/customerio/customerio-ios/commit/cf81b2381993d7108ee7b860d4221c929a98d5d7))

# [1.0.0-alpha.14](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.13...1.0.0-alpha.14) (2021-09-24)


### Features

* rich push images ([#59](https://github.com/customerio/customerio-ios/issues/59)) ([03fc284](https://github.com/customerio/customerio-ios/commit/03fc284f09bb79db53dbc42d78c39acd1204843e))

# [1.0.0-alpha.13](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.12...1.0.0-alpha.13) (2021-09-23)


### Features

* rich push deep links ([#45](https://github.com/customerio/customerio-ios/issues/45)) ([fe21cc8](https://github.com/customerio/customerio-ios/commit/fe21cc87e7146c01df96fbda858e7bd69a6851cb))
* track push events ([#47](https://github.com/customerio/customerio-ios/issues/47)) ([a37e60e](https://github.com/customerio/customerio-ios/commit/a37e60ef390e8cb9c4693c08ae21221186fe8dd2))

# [1.0.0-alpha.13](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.12...1.0.0-alpha.13) (2021-09-22)


### Features

* track push events ([#47](https://github.com/customerio/customerio-ios/issues/47)) ([a37e60e](https://github.com/customerio/customerio-ios/commit/a37e60ef390e8cb9c4693c08ae21221186fe8dd2))

# [1.0.0-alpha.12](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.11...1.0.0-alpha.12) (2021-09-21)


### Features

* register device token with FCM ([#46](https://github.com/customerio/customerio-ios/issues/46)) ([f6a87e0](https://github.com/customerio/customerio-ios/commit/f6a87e0e889b9fdac2c8093a8f4fb4f5f0e9ea2a))

# [1.0.0-alpha.11](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.10...1.0.0-alpha.11) (2021-09-20)


### Features

* event tracking ([#42](https://github.com/customerio/customerio-ios/issues/42)) ([be768bb](https://github.com/customerio/customerio-ios/commit/be768bbb32680ac0ca8dce098f62720394965f85))

# [1.0.0-alpha.10](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.9...1.0.0-alpha.10) (2021-09-15)


### Bug Fixes

* remove apn device token profile request body ([#41](https://github.com/customerio/customerio-ios/issues/41)) ([61946c4](https://github.com/customerio/customerio-ios/commit/61946c4dea617561891188aa537277cc67af35ae))

# [1.0.0-alpha.9](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.8...1.0.0-alpha.9) (2021-09-15)


### Bug Fixes

* call callback on main thread APN tokens ([#40](https://github.com/customerio/customerio-ios/issues/40)) ([982ce9d](https://github.com/customerio/customerio-ios/commit/982ce9d9a8277d72d3fa49c66537a0a6f5b6401a))

# [1.0.0-alpha.8](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.7...1.0.0-alpha.8) (2021-09-15)


### Bug Fixes

* convert APN device token to string ([#39](https://github.com/customerio/customerio-ios/issues/39)) ([1f64a13](https://github.com/customerio/customerio-ios/commit/1f64a13467966f077642745d9f60a168113bdbff))

# [1.0.0-alpha.7](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.6...1.0.0-alpha.7) (2021-09-13)


### Features

* create mocks for push messaging ([#35](https://github.com/customerio/customerio-ios/issues/35)) ([b2c5d62](https://github.com/customerio/customerio-ios/commit/b2c5d6221434e9c559bf818790c48d31decf7f77))

# [1.0.0-alpha.6](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.5...1.0.0-alpha.6) (2021-09-13)


### Bug Fixes

* rename singletons instance to shared ([#34](https://github.com/customerio/customerio-ios/issues/34)) ([3bf1384](https://github.com/customerio/customerio-ios/commit/3bf1384ce9b2d4a8551bb353c1b0e6ce195378df))

# [1.0.0-alpha.5](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.4...1.0.0-alpha.5) (2021-09-10)


### Features

* register/delete device tokens ([#26](https://github.com/customerio/customerio-ios/issues/26)) ([d0ddc07](https://github.com/customerio/customerio-ios/commit/d0ddc07c6b2c25e1168be47e61821e78f5c158a5))

# [1.0.0-alpha.4](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.3...1.0.0-alpha.4) (2021-09-10)


### Bug Fixes

* rename stop identify function ([#31](https://github.com/customerio/customerio-ios/issues/31)) ([d97e931](https://github.com/customerio/customerio-ios/commit/d97e931fa7a001e7a58658471244dcfc1494a386))

# [1.0.0-alpha.3](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.2...1.0.0-alpha.3) (2021-09-10)


### Features

* save all siteids registered with SDK ([#30](https://github.com/customerio/customerio-ios/issues/30)) ([95db6dc](https://github.com/customerio/customerio-ios/commit/95db6dc9462a892f8c46d083be85a97dde1e0b76))

# [1.0.0-alpha.2](https://github.com/customerio/customerio-ios/compare/1.0.0-alpha.1...1.0.0-alpha.2) (2021-09-09)


### Features

* make US default region ([#28](https://github.com/customerio/customerio-ios/issues/28)) ([1d10a8f](https://github.com/customerio/customerio-ios/commit/1d10a8ffc773bf82f0b20abde09fbb95b01797e5))

# 1.0.0-alpha.1 (2021-09-09)


### Features

* identify customer ([#27](https://github.com/customerio/customerio-ios/issues/27)) ([f79d1c9](https://github.com/customerio/customerio-ios/commit/f79d1c9737f215beef4b69167db31ac0d51a16dd))
