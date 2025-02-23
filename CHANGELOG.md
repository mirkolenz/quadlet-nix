# Changelog

## [1.1.5](https://github.com/mirkolenz/quadlet-nix/compare/v1.1.4...v1.1.5) (2025-02-23)

### Bug Fixes

* **network:** delete on stop ([8cd9b2e](https://github.com/mirkolenz/quadlet-nix/commit/8cd9b2ee7fd37443b22968f4d39174a6f8ee5ba9))

## [1.1.4](https://github.com/mirkolenz/quadlet-nix/compare/v1.1.3...v1.1.4) (2025-02-23)

### Bug Fixes

* restart kubes and pods as well ([22604dc](https://github.com/mirkolenz/quadlet-nix/commit/22604dc8f1d3c810942280030cc6bba107f60d78))

## [1.1.3](https://github.com/mirkolenz/quadlet-nix/compare/v1.1.2...v1.1.3) (2025-02-23)

### Bug Fixes

* only restart containers ([02fc405](https://github.com/mirkolenz/quadlet-nix/commit/02fc405e520fd01df9734a91c1b94a941fd781db))

## [1.1.2](https://github.com/mirkolenz/quadlet-nix/compare/v1.1.1...v1.1.2) (2025-02-16)

### Bug Fixes

* **lib:** no longer depend on upstream nixos/systemd utils ([ac2f199](https://github.com/mirkolenz/quadlet-nix/commit/ac2f1996dce23c842834dbd16cb4299d7d03ca6c))

## [1.1.1](https://github.com/mirkolenz/quadlet-nix/compare/v1.1.0...v1.1.1) (2025-02-09)

### Bug Fixes

* add `enable` option ([91306de](https://github.com/mirkolenz/quadlet-nix/commit/91306dedbe6c168c41e03cbcf74c0c85b3e6f36f))
* add homeModules alias ([60f880c](https://github.com/mirkolenz/quadlet-nix/commit/60f880cb6e1249a7054900f5b60297c95bc93888))
* properly handle `enable` option ([15efa3f](https://github.com/mirkolenz/quadlet-nix/commit/15efa3f08c38daf82a061853ea0dfcd8e080dd1a))

## [1.1.0](https://github.com/mirkolenz/quadlet-nix/compare/v1.0.1...v1.1.0) (2025-02-01)

### Features

* add extraConfig and rawConfig ([2269f9b](https://github.com/mirkolenz/quadlet-nix/commit/2269f9bcf1c6dac9521d176e240bbe88cf38d37d))
* add top-level install options ([673043c](https://github.com/mirkolenz/quadlet-nix/commit/673043caec399da75cf9c623f833b6152d8ef31b))

### Bug Fixes

* handle attrset type in unit config values ([0c8ceb0](https://github.com/mirkolenz/quadlet-nix/commit/0c8ceb0c1a7e841e26542d2787361c44b0209396))
* no longer modify exec search path ([64a9b46](https://github.com/mirkolenz/quadlet-nix/commit/64a9b468ba5208b95832848387df1139574addf4))

## [1.0.1](https://github.com/mirkolenz/quadlet-nix/compare/v1.0.0...v1.0.1) (2025-01-20)

### Bug Fixes

* trigger release to build website ([e992704](https://github.com/mirkolenz/quadlet-nix/commit/e992704eddcce5c8a8f5fbe99f4b7346f7566f57))

## 1.0.0 (2025-01-16)

### Features

* add initial home manager module ([66e42b0](https://github.com/mirkolenz/quadlet-nix/commit/66e42b078be374cb4c24a4deb395057636ee4e97))
* add initial version of docs module ([f37df54](https://github.com/mirkolenz/quadlet-nix/commit/f37df5443be2ba494af1a5bdd3f989370b02b385))
* improve auto-update service for nixos and port to hm ([beb61ba](https://github.com/mirkolenz/quadlet-nix/commit/beb61ba4f6933712cdcfaee04e1e9379b3462d4f))
* initial commit ([5aa31a0](https://github.com/mirkolenz/quadlet-nix/commit/5aa31a0fd13e4105ccf7c32e6c26f91de7e72588))

### Bug Fixes

* disable auto update for nix-built images ([8146164](https://github.com/mirkolenz/quadlet-nix/commit/8146164cf504351b5c8ef94b8e06e92c095d36cf))
* **docs:** add pkgs to modules ([d385069](https://github.com/mirkolenz/quadlet-nix/commit/d385069ea6cefe624c1651481b9c13b08191e8c1))
* **docs:** correctly import nixos module ([1b81965](https://github.com/mirkolenz/quadlet-nix/commit/1b81965cfe5f5a0676bc78ffe2eef2a0a024b0cd))
* improve systemd overrides ([e10cb25](https://github.com/mirkolenz/quadlet-nix/commit/e10cb2509ba07329c939ce9d5d288982ae02fa28))
* reorganize modules and improve them ([933ad5c](https://github.com/mirkolenz/quadlet-nix/commit/933ad5cc101ba000d6ffe1792a5466b5f36dd3e9))
* replace concatMapAttrsStringSep for better compatibility ([da8a058](https://github.com/mirkolenz/quadlet-nix/commit/da8a0582f0405b47e5ce7f2f2fc765ac1cf09435))
* rootless podman units work now ([f7963b4](https://github.com/mirkolenz/quadlet-nix/commit/f7963b40c8479f51f3f79a5dfc8d364a6ed5a285))
* update service override search path ([eb189d3](https://github.com/mirkolenz/quadlet-nix/commit/eb189d3ce0b918f620c37168baa551a08db72041))
