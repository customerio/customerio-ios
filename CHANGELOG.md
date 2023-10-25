## [2.8.4](https://github.com/customerio/customerio-ios/compare/2.8.3...2.8.4) (2023-10-18)


### Bug Fixes

* in-app positioning and persistence ([#393](https://github.com/customerio/customerio-ios/issues/393)) ([b5a2f18](https://github.com/customerio/customerio-ios/commit/b5a2f18688e2d6d139f25016ecd0215e4da259c6))

## [2.8.3](https://github.com/customerio/customerio-ios/compare/2.8.2...2.8.3) (2023-10-11)


### Bug Fixes

* prevent registering device with empty identifier existing BQ tasks ([#392](https://github.com/customerio/customerio-ios/issues/392)) ([867619f](https://github.com/customerio/customerio-ios/commit/867619f4885e0c2e438b55826557c3fa5649b035))

## [2.8.2](https://github.com/customerio/customerio-ios/compare/2.8.1...2.8.2) (2023-09-07)


### Bug Fixes

* reduce memory and cpu usage while running background queue ([#379](https://github.com/customerio/customerio-ios/issues/379)) ([87a7eed](https://github.com/customerio/customerio-ios/commit/87a7eed5dc8e101a0d1c3f0b6e83d8b7d637cfcb))

## [2.8.1](https://github.com/customerio/customerio-ios/compare/2.8.0...2.8.1) (2023-08-31)


### Bug Fixes

* added url path encoding ([#376](https://github.com/customerio/customerio-ios/issues/376)) ([fbfa384](https://github.com/customerio/customerio-ios/commit/fbfa384428fdcf3ea69d623e9728a76c4d5d0416))

## [2.8.0](https://github.com/customerio/customerio-ios/compare/2.7.8...2.8.0) (2023-08-31)


### Features

* filter automatic screenview tracking events ([#367](https://github.com/customerio/customerio-ios/issues/367)) ([1a535f9](https://github.com/customerio/customerio-ios/commit/1a535f96761fbeb1a31a7d0820cab77ec4e12c5f))

## [2.7.8](https://github.com/customerio/customerio-ios/compare/2.7.7...2.7.8) (2023-08-14)


### Bug Fixes

* cache queue inventory for lower CPU usage while running queue ([#368](https://github.com/customerio/customerio-ios/issues/368)) ([fdcb24c](https://github.com/customerio/customerio-ios/commit/fdcb24c4f68ca027458036920b09961e819af644))

## [2.7.7](https://github.com/customerio/customerio-ios/compare/2.7.6...2.7.7) (2023-07-26)


### Bug Fixes

* support json array in attributes ([#358](https://github.com/customerio/customerio-ios/issues/358)) ([a634358](https://github.com/customerio/customerio-ios/commit/a63435833b57f2a1405d018f158c1e945bf6c73d))

## [2.7.6](https://github.com/customerio/customerio-ios/compare/2.7.5...2.7.6) (2023-07-21)


### Bug Fixes

* apps initializing sdk multiple times in short amount of time may make SDK ignore requests ([#360](https://github.com/customerio/customerio-ios/issues/360)) ([09829e0](https://github.com/customerio/customerio-ios/commit/09829e0c55b3637d82059087bf72b1f1d14b0e59))

## [2.7.5](https://github.com/customerio/customerio-ios/compare/2.7.4...2.7.5) (2023-07-20)


### Bug Fixes

* deinit cleanup repo bad memory access ([#356](https://github.com/customerio/customerio-ios/issues/356)) ([0483fb0](https://github.com/customerio/customerio-ios/commit/0483fb04e02228bfe1dd1ff88e9e51e688b477fd))

## [2.7.4](https://github.com/customerio/customerio-ios/compare/2.7.3...2.7.4) (2023-07-17)


### Bug Fixes

* save device token in SDK even if no profile identified ([#354](https://github.com/customerio/customerio-ios/issues/354)) ([a49f72c](https://github.com/customerio/customerio-ios/commit/a49f72ce94549d4e9d754891e3b6f6b309f46e8a))

## [2.7.3](https://github.com/customerio/customerio-ios/compare/2.7.2...2.7.3) (2023-07-17)


### Bug Fixes

* prevent api calls when identifier is empty ([#353](https://github.com/customerio/customerio-ios/issues/353)) ([10b5db7](https://github.com/customerio/customerio-ios/commit/10b5db739444074847fb6e58e6554411e0a5fa74))

## [2.7.2](https://github.com/customerio/customerio-ios/compare/2.7.1...2.7.2) (2023-07-12)


### Bug Fixes

* gist migration to CIO ([#338](https://github.com/customerio/customerio-ios/issues/338)) ([#351](https://github.com/customerio/customerio-ios/issues/351)) ([5520a7c](https://github.com/customerio/customerio-ios/commit/5520a7ceb4d35170b4bf2d2493ceb9576ea8d3cf))

## [2.7.1](https://github.com/customerio/customerio-ios/compare/2.7.0...2.7.1) (2023-07-04)


### Bug Fixes

* bad memory access crash ([#342](https://github.com/customerio/customerio-ios/issues/342)) ([b83e6bd](https://github.com/customerio/customerio-ios/commit/b83e6bda1a0746eab65bb3d07887c3fcbcb67712))

## [2.7.0](https://github.com/customerio/customerio-ios/compare/2.6.1...2.7.0) (2023-06-21)


### Features

* include FCM SDK as a dependency to make FCM push setup easier ([#333](https://github.com/customerio/customerio-ios/issues/333)) ([233fc22](https://github.com/customerio/customerio-ios/commit/233fc228f768fb9e1a98dffd2b5c9d49d34c9cc2))

### [2.6.1](https://github.com/customerio/customerio-ios/compare/2.6.0...2.6.1) (2023-05-26)


### Bug Fixes

* internal module Common clashing with other Common modules in customers app ([#328](https://github.com/customerio/customerio-ios/issues/328)) ([817dd56](https://github.com/customerio/customerio-ios/commit/817dd5692c412e91b1edbac9af64c0f4844a4cb4))

## [2.6.0](https://github.com/customerio/customerio-ios/compare/2.5.3...2.6.0) (2023-05-26)


### Features

* in-app dismiss message ([#320](https://github.com/customerio/customerio-ios/issues/320)) ([e067001](https://github.com/customerio/customerio-ios/commit/e067001628423a2dc4d9a5c1836a9d985cf60150))

### [2.5.3](https://github.com/customerio/customerio-ios/compare/2.5.2...2.5.3) (2023-05-26)


### Bug Fixes

* in-app universal link redirection support ([#329](https://github.com/customerio/customerio-ios/issues/329)) ([51470e8](https://github.com/customerio/customerio-ios/commit/51470e80270092da1948f04a388aedaf0f2fcf35))

### [2.5.2](https://github.com/customerio/customerio-ios/compare/2.5.1...2.5.2) (2023-05-19)


### Bug Fixes

* exact version for gist ([#321](https://github.com/customerio/customerio-ios/issues/321)) ([4b75cc5](https://github.com/customerio/customerio-ios/commit/4b75cc53e8f15a5496df17e825e12b4f44c3efef))

### [2.5.2](https://github.com/customerio/customerio-ios/compare/2.5.1...2.5.2) (2023-05-19)


### Bug Fixes

* exact version for gist ([#321](https://github.com/customerio/customerio-ios/issues/321)) ([4b75cc5](https://github.com/customerio/customerio-ios/commit/4b75cc53e8f15a5496df17e825e12b4f44c3efef))

### [2.5.1](https://github.com/customerio/customerio-ios/compare/2.5.0...2.5.1) (2023-05-12)


### Bug Fixes

* sdk wrappers not having device token registered because of application lifecycle ([#285](https://github.com/customerio/customerio-ios/issues/285)) ([da7fc51](https://github.com/customerio/customerio-ios/commit/da7fc512e9308af208de8dea5aeaf95839a52fc1))

## [2.5.0](https://github.com/customerio/customerio-ios/compare/2.4.1...2.5.0) (2023-04-27)


### Features

* expose current SDK config options for reference ([#298](https://github.com/customerio/customerio-ios/issues/298)) ([6ac739b](https://github.com/customerio/customerio-ios/commit/6ac739b1550636db10230d8b2c10783f46626250))

### [2.4.1](https://github.com/customerio/customerio-ios/compare/2.4.0...2.4.1) (2023-04-27)


### Bug Fixes

* auto update gist in CocoaPods ([#303](https://github.com/customerio/customerio-ios/issues/303)) ([6096d17](https://github.com/customerio/customerio-ios/commit/6096d176cdc52e7e8a949960bfb9c4aa1541c8fd))

## [2.4.0](https://github.com/customerio/customerio-ios/compare/2.3.0...2.4.0) (2023-04-27)


### Features

* get the version of the SDK ([#299](https://github.com/customerio/customerio-ios/issues/299)) ([38a6b00](https://github.com/customerio/customerio-ios/commit/38a6b0061f0f5b317f592ec885f8746c65ab8ba5))

## [2.3.0](https://github.com/customerio/customerio-ios/compare/2.2.0...2.3.0) (2023-04-19)


### Features

* in app click tracking ([#284](https://github.com/customerio/customerio-ios/issues/284)) ([4ed8edb](https://github.com/customerio/customerio-ios/commit/4ed8edbd0f9e7a7aa6a708e525c6081e93658e98))

## [2.2.0](https://github.com/customerio/customerio-ios/compare/2.1.2...2.2.0) (2023-04-18)


### Features

* ui for new sample app with apns ([#282](https://github.com/customerio/customerio-ios/issues/282)) ([06e4a6b](https://github.com/customerio/customerio-ios/commit/06e4a6b71554610c7e7d3b95f62d129d934414be))

### [2.1.2](https://github.com/customerio/customerio-ios/compare/2.1.1...2.1.2) (2023-03-10)


### Bug Fixes

* delete tasks that returns http 400 ([#276](https://github.com/customerio/customerio-ios/issues/276)) ([aabfe9e](https://github.com/customerio/customerio-ios/commit/aabfe9ec02ec5b40326c60e973cdfa5f9338f85f))

### [2.1.1](https://github.com/customerio/customerio-ios/compare/2.1.0...2.1.1) (2023-03-08)


### Bug Fixes

* cocoapods app extension targets able to compile ([#277](https://github.com/customerio/customerio-ios/issues/277)) ([8dbca8f](https://github.com/customerio/customerio-ios/commit/8dbca8fab912913b5b26652098d5c1958dbdb4fd))

## [2.1.0](https://github.com/customerio/customerio-ios/compare/2.0.6...2.1.0) (2023-02-22)


### Features

* add in-app event listener ([#211](https://github.com/customerio/customerio-ios/issues/211)) ([737d43b](https://github.com/customerio/customerio-ios/commit/737d43b262cb467d6fb0dfc160d558ce3de09bf7))
* in-app feature no longer requires orgId ([#252](https://github.com/customerio/customerio-ios/issues/252)) ([acd12da](https://github.com/customerio/customerio-ios/commit/acd12dab64e119546379f52552f2434843252682))


### Bug Fixes

* access modifier for metric ([#263](https://github.com/customerio/customerio-ios/issues/263)) ([e641982](https://github.com/customerio/customerio-ios/commit/e641982c86e5e4347977f0c0af2615d4541ff0e5))
* added reusable code for wrapper SDKs ([#247](https://github.com/customerio/customerio-ios/issues/247)) ([36adf15](https://github.com/customerio/customerio-ios/commit/36adf158748b7dc439812807fd4d27a287a82e1a))
* in-app missing event ([#259](https://github.com/customerio/customerio-ios/issues/259)) ([43b3e97](https://github.com/customerio/customerio-ios/commit/43b3e9706b152fe2dead882336a3f416ba400b73))
* modify in-app event listener action parameters to new name ([#255](https://github.com/customerio/customerio-ios/issues/255)) ([b46528a](https://github.com/customerio/customerio-ios/commit/b46528a0cd6cda4f8428eef0001032a79338e1cf))
* region visibility modifier to be used by wrappers ([#260](https://github.com/customerio/customerio-ios/issues/260)) ([f0edfbc](https://github.com/customerio/customerio-ios/commit/f0edfbc52a4694b2cee29a431d8c0943f819815b))
* update the gist version in podspec ([#256](https://github.com/customerio/customerio-ios/issues/256)) ([5451488](https://github.com/customerio/customerio-ios/commit/545148820187c04938e717fce4e166cd77a78f92))

### [2.0.6](https://github.com/customerio/customerio-ios/compare/2.0.5...2.0.6) (2023-02-15)


### Bug Fixes

* universal links deep links open host app ([#268](https://github.com/customerio/customerio-ios/issues/268)) ([29c95b5](https://github.com/customerio/customerio-ios/commit/29c95b5b9810f6cdec22a15df643f8d1a9fb7d58))

### [2.0.5](https://github.com/customerio/customerio-ios/compare/2.0.4...2.0.5) (2023-02-10)


### Bug Fixes

* universal links when touch a push notification open host app ([#265](https://github.com/customerio/customerio-ios/issues/265)) ([7dcaf73](https://github.com/customerio/customerio-ios/commit/7dcaf736912e23cbc6dced0206c4a4f53c6e298d))


## [2.1.0-beta.2](https://github.com/customerio/customerio-ios/compare/2.1.0-beta.1...2.1.0-beta.2) (2023-02-09)


### Bug Fixes

* access modifier for metric ([#263](https://github.com/customerio/customerio-ios/issues/263)) ([e641982](https://github.com/customerio/customerio-ios/commit/e641982c86e5e4347977f0c0af2615d4541ff0e5))

## [2.1.0-beta.1](https://github.com/customerio/customerio-ios/compare/2.0.4...2.1.0-beta.1) (2023-02-07)


### Features

* add in-app event listener ([#211](https://github.com/customerio/customerio-ios/issues/211)) ([737d43b](https://github.com/customerio/customerio-ios/commit/737d43b262cb467d6fb0dfc160d558ce3de09bf7))
* in-app feature no longer requires orgId ([#252](https://github.com/customerio/customerio-ios/issues/252)) ([acd12da](https://github.com/customerio/customerio-ios/commit/acd12dab64e119546379f52552f2434843252682))


### Bug Fixes

* added reusable code for wrapper SDKs ([#247](https://github.com/customerio/customerio-ios/issues/247)) ([36adf15](https://github.com/customerio/customerio-ios/commit/36adf158748b7dc439812807fd4d27a287a82e1a))
* in-app missing event ([#259](https://github.com/customerio/customerio-ios/issues/259)) ([43b3e97](https://github.com/customerio/customerio-ios/commit/43b3e9706b152fe2dead882336a3f416ba400b73))
* modify in-app event listener action parameters to new name ([#255](https://github.com/customerio/customerio-ios/issues/255)) ([b46528a](https://github.com/customerio/customerio-ios/commit/b46528a0cd6cda4f8428eef0001032a79338e1cf))
* region visibility modifier to be used by wrappers ([#260](https://github.com/customerio/customerio-ios/issues/260)) ([f0edfbc](https://github.com/customerio/customerio-ios/commit/f0edfbc52a4694b2cee29a431d8c0943f819815b))
* update the gist version in podspec ([#256](https://github.com/customerio/customerio-ios/issues/256)) ([5451488](https://github.com/customerio/customerio-ios/commit/545148820187c04938e717fce4e166cd77a78f92))

### [2.0.4](https://github.com/customerio/customerio-ios/compare/2.0.3...2.0.4) (2023-01-17)


### Bug Fixes

* async running BQ operations in loop ([#250](https://github.com/customerio/customerio-ios/issues/250)) ([f0a3d9c](https://github.com/customerio/customerio-ios/commit/f0a3d9cf6c85d6efa619d748db16f4e04b596e9f))

### [2.0.3](https://github.com/customerio/customerio-ios/compare/2.0.2...2.0.3) (2023-01-11)


### Bug Fixes

* revert 2.0.2 as it was found unstable ([#249](https://github.com/customerio/customerio-ios/issues/249)) ([51b5831](https://github.com/customerio/customerio-ios/commit/51b58314705eaa336e2eeb3579b3ca7df0cfcaab))

### [2.0.2](https://github.com/customerio/customerio-ios/compare/2.0.1...2.0.2) (2023-01-06)


### Bug Fixes

* prevent stackoverflow while executing background queue with lots of tasks in it ([#245](https://github.com/customerio/customerio-ios/issues/245)) ([ef0c428](https://github.com/customerio/customerio-ios/commit/ef0c4285bbe1a908e9695258f84cde26b62eeb80))

### [2.0.1](https://github.com/customerio/customerio-ios/compare/2.0.0...2.0.1) (2022-12-22)


### Bug Fixes

* download rich push images from CDN ([#237](https://github.com/customerio/customerio-ios/issues/237)) ([b30cf02](https://github.com/customerio/customerio-ios/commit/b30cf02f2a27a210fe07e8bea61dc618c5c57b2d))

## [2.0.0](https://github.com/customerio/customerio-ios/compare/1.2.7...2.0.0) (2022-12-13)


### ⚠ BREAKING CHANGES

* make delivered push metric more reliable
* remove FCM dependency from cocoapods (#210)
* singleton API only way to use SDK now (#209)

### Bug Fixes

* add sdkwrapperconfig to rich push SDK config ([#226](https://github.com/customerio/customerio-ios/issues/226)) ([e43b4cf](https://github.com/customerio/customerio-ios/commit/e43b4cfe30c38e118b1c622675bab48c41072d30))
* do not modify custom attributes casing ([#234](https://github.com/customerio/customerio-ios/issues/234)) ([8160fdf](https://github.com/customerio/customerio-ios/commit/8160fdfb07f29a3e450cb8a5481b3ca75622cdce))
* fix compile time errors notification service extensions ([#214](https://github.com/customerio/customerio-ios/issues/214)) ([bd5911b](https://github.com/customerio/customerio-ios/commit/bd5911b1401e26112a900c6a0c6f132c3ab2c27a))
* make delivered push metric more reliable ([0478e52](https://github.com/customerio/customerio-ios/commit/0478e5273017867ecff194905d130cbf32d588ac))
* sdk not able to compile in ios app ([#225](https://github.com/customerio/customerio-ios/issues/225)) ([e4d1b3f](https://github.com/customerio/customerio-ios/commit/e4d1b3f2b4bda91862151947e480b0644d5cc704))


### Code Refactoring

* remove FCM dependency from cocoapods ([#210](https://github.com/customerio/customerio-ios/issues/210)) ([3547076](https://github.com/customerio/customerio-ios/commit/3547076a3694c211f1b11b2a61db7d6debe05a6b))
* singleton API only way to use SDK now ([#209](https://github.com/customerio/customerio-ios/issues/209)) ([72b7477](https://github.com/customerio/customerio-ios/commit/72b7477b16c490b9839fd48f51487e657440a75c))

## [2.0.0-beta.1](https://github.com/customerio/customerio-ios/compare/1.2.7...2.0.0-beta.1) (2022-12-09)


### ⚠ BREAKING CHANGES

* make delivered push metric more reliable
* remove FCM dependency from cocoapods (#210)
* singleton API only way to use SDK now (#209)

### Bug Fixes

* add sdkwrapperconfig to rich push SDK config ([#226](https://github.com/customerio/customerio-ios/issues/226)) ([e43b4cf](https://github.com/customerio/customerio-ios/commit/e43b4cfe30c38e118b1c622675bab48c41072d30))
* do not modify custom attributes casing ([#234](https://github.com/customerio/customerio-ios/issues/234)) ([8160fdf](https://github.com/customerio/customerio-ios/commit/8160fdfb07f29a3e450cb8a5481b3ca75622cdce))
* fix compile time errors notification service extensions ([#214](https://github.com/customerio/customerio-ios/issues/214)) ([bd5911b](https://github.com/customerio/customerio-ios/commit/bd5911b1401e26112a900c6a0c6f132c3ab2c27a))
* make delivered push metric more reliable ([0478e52](https://github.com/customerio/customerio-ios/commit/0478e5273017867ecff194905d130cbf32d588ac))
* sdk not able to compile in ios app ([#225](https://github.com/customerio/customerio-ios/issues/225)) ([e4d1b3f](https://github.com/customerio/customerio-ios/commit/e4d1b3f2b4bda91862151947e480b0644d5cc704))


### Code Refactoring

* remove FCM dependency from cocoapods ([#210](https://github.com/customerio/customerio-ios/issues/210)) ([3547076](https://github.com/customerio/customerio-ios/commit/3547076a3694c211f1b11b2a61db7d6debe05a6b))
* singleton API only way to use SDK now ([#209](https://github.com/customerio/customerio-ios/issues/209)) ([72b7477](https://github.com/customerio/customerio-ios/commit/72b7477b16c490b9839fd48f51487e657440a75c))

### [1.2.7](https://github.com/customerio/customerio-ios/compare/1.2.6...1.2.7) (2022-12-06)


### Bug Fixes

* push images and processing simple push ([#230](https://github.com/customerio/customerio-ios/issues/230)) ([f109f04](https://github.com/customerio/customerio-ios/commit/f109f04d04e2b87ef75707a15818050c7c84b45a))


## [2.0.0-alpha.2](https://github.com/customerio/customerio-ios/compare/2.0.0-alpha.1...2.0.0-alpha.2) (2022-12-02)


### Bug Fixes

* sdk not able to compile in ios app ([#225](https://github.com/customerio/customerio-ios/issues/225)) ([e4d1b3f](https://github.com/customerio/customerio-ios/commit/e4d1b3f2b4bda91862151947e480b0644d5cc704))

## [2.0.0-alpha.1](https://github.com/customerio/customerio-ios/compare/1.2.6...2.0.0-alpha.1) (2022-11-30)


### ⚠ BREAKING CHANGES

* make delivered push metric more reliable
* remove FCM dependency from cocoapods (#210)
* singleton API only way to use SDK now (#209)

### Bug Fixes

* fix compile time errors notification service extensions ([#214](https://github.com/customerio/customerio-ios/issues/214)) ([bd5911b](https://github.com/customerio/customerio-ios/commit/bd5911b1401e26112a900c6a0c6f132c3ab2c27a))
* make delivered push metric more reliable ([0478e52](https://github.com/customerio/customerio-ios/commit/0478e5273017867ecff194905d130cbf32d588ac))


### Code Refactoring

* remove FCM dependency from cocoapods ([#210](https://github.com/customerio/customerio-ios/issues/210)) ([3547076](https://github.com/customerio/customerio-ios/commit/3547076a3694c211f1b11b2a61db7d6debe05a6b))
* singleton API only way to use SDK now ([#209](https://github.com/customerio/customerio-ios/issues/209)) ([72b7477](https://github.com/customerio/customerio-ios/commit/72b7477b16c490b9839fd48f51487e657440a75c))

### [1.2.6](https://github.com/customerio/customerio-ios/compare/1.2.5...1.2.6) (2022-11-17)


### Bug Fixes

* device attributes shows sdk version instead of wrapper version ([e2462b9](https://github.com/customerio/customerio-ios/commit/e2462b9408fdaba2b690e3d1209aa17680457d92))

### [1.2.5](https://github.com/customerio/customerio-ios/compare/1.2.4...1.2.5) (2022-11-14)


### Bug Fixes

* fix compile time errors notification service extensions ([#216](https://github.com/customerio/customerio-ios/issues/216)) ([6e8484a](https://github.com/customerio/customerio-ios/commit/6e8484af6fc72c0e77cfd3d60bbb3fe808d067a8))

### [1.2.4](https://github.com/customerio/customerio-ios/compare/1.2.3...1.2.4) (2022-11-11)


### Bug Fixes

* updated gist version in podspec ([ab231b1](https://github.com/customerio/customerio-ios/commit/ab231b169208fb869fb1083869ee4c0cb854728b))

### [1.2.3](https://github.com/customerio/customerio-ios/compare/1.2.2...1.2.3) (2022-11-10)


### Bug Fixes

* install in-app bug fix via gist 2.2.1 ([38d64fd](https://github.com/customerio/customerio-ios/commit/38d64fd69ce5947a097c5cb3d249d40f74149ff0))

### [1.2.2](https://github.com/customerio/customerio-ios/compare/1.2.1...1.2.2) (2022-10-31)


### Bug Fixes

* updating gist dependency version ([0b8569c](https://github.com/customerio/customerio-ios/commit/0b8569ce0d11feb35e62be30d2788077f94f6016))

### [1.2.1](https://github.com/customerio/customerio-ios/compare/1.2.0...1.2.1) (2022-10-25)


### Bug Fixes

* added expo and flutter values in source enum ([274aa1c](https://github.com/customerio/customerio-ios/commit/274aa1ca6911636e285a8a3a509a891434d16614))

## [1.2.0](https://github.com/customerio/customerio-ios/compare/1.1.1...1.2.0) (2022-10-17)


### Features

* allow option to handle deep link yourself ([#177](https://github.com/customerio/customerio-ios/issues/177)) ([b8167ea](https://github.com/customerio/customerio-ios/commit/b8167ea6c34f5f863b597ee7e365377ff5c33dea))
* delete expired queue tasks ([dc22280](https://github.com/customerio/customerio-ios/commit/dc22280afd3c7a9e721e7e1105954f9656cbc7ea))
* in-app into develop to promote to alpha ([2b2712c](https://github.com/customerio/customerio-ios/commit/2b2712c09be4baf7dabd27af5af00d8a5e2d859d))
* sdk wrappers modify user-agent ([5c127e5](https://github.com/customerio/customerio-ios/commit/5c127e5f32a16e568f4fd969094223130de42e36))


### Bug Fixes

* cocoapods compiling of SDK ([a20e583](https://github.com/customerio/customerio-ios/commit/a20e58342bf5175cd42934cb778cedd1402dcb0f))
* compile sdk without xcode error app extensions ([#185](https://github.com/customerio/customerio-ios/issues/185)) ([5fc0fd5](https://github.com/customerio/customerio-ios/commit/5fc0fd5809ac6be4002605bb28a7649b664272f1))
* consolidate all apple platforms under ios ([423f050](https://github.com/customerio/customerio-ios/commit/423f05037fcfbfc7035e8317a52865b64601f8b4))
* deprecating creating own instances ([#202](https://github.com/customerio/customerio-ios/issues/202)) ([18859e6](https://github.com/customerio/customerio-ios/commit/18859e6c4b78365610b92f61eb12b3923c858941))
* image not shown in rich push notification ([9fb8490](https://github.com/customerio/customerio-ios/commit/9fb8490ae7bc068dd8ab11348b5cf1290da5b79e))
* improve reliability of screen view tracking ([60e9289](https://github.com/customerio/customerio-ios/commit/60e9289930485d3394911490bf6f05c7d1af521c))
* make sdkwrapperconfig accessible ([#188](https://github.com/customerio/customerio-ios/issues/188)) ([f996a68](https://github.com/customerio/customerio-ios/commit/f996a682dd1eedfc4f37bbd82644541423f4b8d6))
* queue attempts to run all tasks on each run ([80f90e9](https://github.com/customerio/customerio-ios/commit/80f90e97e9f9c76e7d235b2065c799c396414236))
* restricting create own instance ([085735c](https://github.com/customerio/customerio-ios/commit/085735ca08eb21b012f586ea6008d7e732a4e66f))
* some classes not found in tracking module ([45f178e](https://github.com/customerio/customerio-ios/commit/45f178ecd670514864194611506d652a5e8cd4b9))
* updating gist dependency version ([23c432e](https://github.com/customerio/customerio-ios/commit/23c432e520176aca1b1bdd39d25dffa8d4b7aa90))

## [1.2.0-beta.4](https://github.com/customerio/customerio-ios/compare/1.2.0-beta.3...1.2.0-beta.4) (2022-10-13)


### Bug Fixes

* restricting create own instance ([085735c](https://github.com/customerio/customerio-ios/commit/085735ca08eb21b012f586ea6008d7e732a4e66f))

## [1.2.0-beta.3](https://github.com/customerio/customerio-ios/compare/1.2.0-beta.2...1.2.0-beta.3) (2022-10-07)


### Bug Fixes

* deprecating creating own instances ([#202](https://github.com/customerio/customerio-ios/issues/202)) ([18859e6](https://github.com/customerio/customerio-ios/commit/18859e6c4b78365610b92f61eb12b3923c858941))

## [1.2.0-beta.2](https://github.com/customerio/customerio-ios/compare/1.2.0-beta.1...1.2.0-beta.2) (2022-10-04)


### Bug Fixes

* updating gist dependency version ([23c432e](https://github.com/customerio/customerio-ios/commit/23c432e520176aca1b1bdd39d25dffa8d4b7aa90))

## [1.2.0-beta.1](https://github.com/customerio/customerio-ios/compare/1.1.1...1.2.0-beta.1) (2022-09-08)


### Features

* allow option to handle deep link yourself ([#177](https://github.com/customerio/customerio-ios/issues/177)) ([b8167ea](https://github.com/customerio/customerio-ios/commit/b8167ea6c34f5f863b597ee7e365377ff5c33dea))
* delete expired queue tasks ([dc22280](https://github.com/customerio/customerio-ios/commit/dc22280afd3c7a9e721e7e1105954f9656cbc7ea))
* in-app into develop to promote to alpha ([2b2712c](https://github.com/customerio/customerio-ios/commit/2b2712c09be4baf7dabd27af5af00d8a5e2d859d))
* sdk wrappers modify user-agent ([5c127e5](https://github.com/customerio/customerio-ios/commit/5c127e5f32a16e568f4fd969094223130de42e36))


### Bug Fixes

* cocoapods compiling of SDK ([a20e583](https://github.com/customerio/customerio-ios/commit/a20e58342bf5175cd42934cb778cedd1402dcb0f))
* compile sdk without xcode error app extensions ([#185](https://github.com/customerio/customerio-ios/issues/185)) ([5fc0fd5](https://github.com/customerio/customerio-ios/commit/5fc0fd5809ac6be4002605bb28a7649b664272f1))
* consolidate all apple platforms under ios ([423f050](https://github.com/customerio/customerio-ios/commit/423f05037fcfbfc7035e8317a52865b64601f8b4))
* image not shown in rich push notification ([9fb8490](https://github.com/customerio/customerio-ios/commit/9fb8490ae7bc068dd8ab11348b5cf1290da5b79e))
* improve reliability of screen view tracking ([60e9289](https://github.com/customerio/customerio-ios/commit/60e9289930485d3394911490bf6f05c7d1af521c))
* make sdkwrapperconfig accessible ([#188](https://github.com/customerio/customerio-ios/issues/188)) ([f996a68](https://github.com/customerio/customerio-ios/commit/f996a682dd1eedfc4f37bbd82644541423f4b8d6))
* queue attempts to run all tasks on each run ([80f90e9](https://github.com/customerio/customerio-ios/commit/80f90e97e9f9c76e7d235b2065c799c396414236))
* some classes not found in tracking module ([45f178e](https://github.com/customerio/customerio-ios/commit/45f178ecd670514864194611506d652a5e8cd4b9))

## [1.2.0-alpha.4](https://github.com/customerio/customerio-ios/compare/1.2.0-alpha.3...1.2.0-alpha.4) (2022-09-01)


### Bug Fixes

* consolidate all apple platforms under ios ([423f050](https://github.com/customerio/customerio-ios/commit/423f05037fcfbfc7035e8317a52865b64601f8b4))
* image not shown in rich push notification ([9fb8490](https://github.com/customerio/customerio-ios/commit/9fb8490ae7bc068dd8ab11348b5cf1290da5b79e))

## [1.2.0-alpha.3](https://github.com/customerio/customerio-ios/compare/1.2.0-alpha.2...1.2.0-alpha.3) (2022-08-05)


### Features

* in-app into develop to promote to alpha ([2b2712c](https://github.com/customerio/customerio-ios/commit/2b2712c09be4baf7dabd27af5af00d8a5e2d859d))


### Bug Fixes

* make sdkwrapperconfig accessible ([#188](https://github.com/customerio/customerio-ios/issues/188)) ([f996a68](https://github.com/customerio/customerio-ios/commit/f996a682dd1eedfc4f37bbd82644541423f4b8d6))

## [1.2.0-alpha.2](https://github.com/customerio/customerio-ios/compare/1.2.0-alpha.1...1.2.0-alpha.2) (2022-07-26)


### Features

* allow option to handle deep link yourself ([#177](https://github.com/customerio/customerio-ios/issues/177)) ([b8167ea](https://github.com/customerio/customerio-ios/commit/b8167ea6c34f5f863b597ee7e365377ff5c33dea))


### Bug Fixes

* cocoapods compiling of SDK ([a20e583](https://github.com/customerio/customerio-ios/commit/a20e58342bf5175cd42934cb778cedd1402dcb0f))
* compile sdk without xcode error app extensions ([#185](https://github.com/customerio/customerio-ios/issues/185)) ([5fc0fd5](https://github.com/customerio/customerio-ios/commit/5fc0fd5809ac6be4002605bb28a7649b664272f1))

## [1.2.0-alpha.1](https://github.com/customerio/customerio-ios/compare/1.1.1...1.2.0-alpha.1) (2022-07-25)


### Features

* delete expired queue tasks ([dc22280](https://github.com/customerio/customerio-ios/commit/dc22280afd3c7a9e721e7e1105954f9656cbc7ea))
* sdk wrappers modify user-agent ([5c127e5](https://github.com/customerio/customerio-ios/commit/5c127e5f32a16e568f4fd969094223130de42e36))


### Bug Fixes

* improve reliability of screen view tracking ([60e9289](https://github.com/customerio/customerio-ios/commit/60e9289930485d3394911490bf6f05c7d1af521c))
* queue attempts to run all tasks on each run ([80f90e9](https://github.com/customerio/customerio-ios/commit/80f90e97e9f9c76e7d235b2065c799c396414236))
* some classes not found in tracking module ([45f178e](https://github.com/customerio/customerio-ios/commit/45f178ecd670514864194611506d652a5e8cd4b9))

### [1.1.1](https://github.com/customerio/customerio-ios/compare/1.1.0...1.1.1) (2022-06-10)


### Bug Fixes

* send attributes in all caps to API ([9eea27b](https://github.com/customerio/customerio-ios/commit/9eea27b29e11b2fed75bfe584f0a98f923e393fc))

## [1.1.0](https://github.com/customerio/customerio-ios/compare/1.0.3...1.1.0) (2022-06-01)


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
