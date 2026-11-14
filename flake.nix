{
  description = "Logos Blockchain Module - Qt6 Plugin";

  # Pull pre-built artifacts from the self-hosted Logos Attic cache(Nix binary cache).
  nixConfig = {
    extra-substituters = [ "https://cache.nix.logos.co/public" ];
    extra-trusted-public-keys = [ "public:l4HrXgL4nw246+LBh2SOJyhz64BoGegOYLheT/iIAPU=" ];
  };

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder/0.3.1";
    logos-blockchain.url = "github:logos-blockchain/logos-blockchain?ref=0.3.4";
    # Windows (x86_64-w64-mingw32) build of the node's C library (liblogos_blockchain.dll
    # + import lib + header): logos-blockchain 0.3.4 + the logos-node-windows patches,
    # built natively with MSYS2 MinGW64 and fully static runtime (imports only system DLLs).
    # See WINDOWS.md. Only used for the x86_64-windows target.
    logos-blockchain-win = {
      url = "https://github.com/yayguru/logos-blockchain-module/releases/download/v0.3.4-windows.2/logos_blockchain-0.3.4-windows-x86_64-gnu.tar.gz";
      flake = false;
    };
  };

  outputs = inputs@{ self, logos-module-builder, ... }:
    let
      nixpkgs = logos-module-builder.inputs.nixpkgs;

      # Prebuilt Windows node library, staged in the layout the builder expects
      # (lib/ = .dll + .dll.a, include/ = header).
      # Windows cross package set the builder itself uses (logos-nix mkWindowsPkgs).
      winPkgs = logos-module-builder.inputs.logos-nix.lib.mkWindowsPkgs { buildSystem = "x86_64-linux"; };

      # nixpkgs' libfyaml uses the autotools build, which cannot target mingw
      # (needs pthreads, and its tool includes a header the dist tarball lacks).
      # libfyaml 0.9.6 supports Windows through its CMake build; use that.
      fyamlWin = winPkgs.libfyaml.overrideAttrs (o: {
        nativeBuildInputs = [ winPkgs.buildPackages.cmake winPkgs.buildPackages.pkg-config winPkgs.buildPackages.ninja ];
        buildInputs = [ winPkgs.windows.pthreads ];
        configurePhase = null;
        autoreconfPhase = null;
        dontUseCmakeConfigure = false;
        preConfigure = "";
        # The generated .def names the module "fyaml", so the import library
        # records fyaml.dll while MinGW writes libfyaml.dll: anything linked
        # against it would look for a DLL that does not exist. Name it after
        # the file that is actually produced.
        postPatch = ''
          substituteInPlace cmake/generate-def.cmake \
            --replace-fail 'LIBRARY fyaml' 'LIBRARY libfyaml'
        '';
        cmakeFlags = [ "-DBUILD_TESTING=OFF" "-DENABLE_NETWORK=OFF" "-DENABLE_PORTABLE_TARGET=ON" "-DBUILD_SHARED_LIBS=ON" ];
        doCheck = false;
        outputs = [ "out" ];
        # 0.9.6's public headers cannot be included from C++ with g++: the
        # atomics header enables C11 `_Atomic` for any non-strict GCC (g++ has
        # no `_Atomic`) and its non-atomic fallback does not compile. The patch
        # maps the C11 atomics onto <atomic> in C++ (as C++23 <stdatomic.h>
        # does). Only the installed headers change; the C library is untouched.
        postInstall = ''
          patch -d $out -p1 < ${./patches/libfyaml-0.9.6-cxx-atomics.patch}
        '';
        postFixup = "";
      });

      winLib = nixpkgs.legacyPackages.x86_64-linux.runCommand "logos-blockchain-c-0.3.4-win64" {} ''
        mkdir -p $out/lib $out/include
        # Rust's windows-gnu cdylib is named logos_blockchain.dll (no lib prefix);
        # the import library records that name, so it is shipped under it.
        cp ${inputs.logos-blockchain-win}/logos_blockchain.dll $out/lib/
        cp ${inputs.logos-blockchain-win}/liblogos_blockchain.dll.a $out/lib/
        cp ${inputs.logos-blockchain-win}/logos_blockchain.h $out/include/
      '';
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = fn: nixpkgs.lib.genAttrs systems fn;

      moduleArgs = {
        src = ./.;
        configFile = ./metadata.json;
        flakeInputs = inputs;

        externalLibInputs = {
          # Every native system builds the node from source as upstream does; the
          # Windows cross target links the prebuilt MinGW library instead (the
          # upstream circuits' Windows archives are not linkable as shipped).
          logos_blockchain = {
            packages = inputs.logos-blockchain.packages // {
              x86_64-windows.default = winLib;
            };
          };
          # Windows only (metadata.json nix.platforms); the native entries are
          # never linked, they only keep every system's evaluation total.
          fyaml = {
            packages = forAllSystems (system: {
              default = nixpkgs.legacyPackages.${system}.libfyaml;
            }) // {
              x86_64-windows.default = fyamlWin;
            };
          };
        };

        tests = {
          dir = ./tests;
          mockCLibs = [ "logos_blockchain" ];
        };

        postInstall = ''
          # Remove nix references to make the module portable.
          find "$out" -type f | while read -r binary; do
            if file "$binary" | grep -E -q "Mach-O|shared library|executable|archive"; then
              echo "Scrubbing references inside verified target: $binary"
              chmod +w "$binary" 2>/dev/null || true

              perl -pi -e 's|/nix/store/[a-z0-9]{32}-boost|/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-boost|g' "$binary" 2>/dev/null || true
              perl -pi -e 's|/nix/store/[a-z0-9]{32}-nlohmann_json|/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-nlohmann_json|g' "$binary" 2>/dev/null || true
              perl -pi -e 's|/nix/store/[a-z0-9]{32}-vendor-cargo-deps|/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-vendor-cargo-deps|g' "$binary" 2>/dev/null || true
              perl -pi -e 's|/nix/var/nix/b/[a-z0-9]{26}/|/tmp/eeeeeeeeeeeeeeeeeeeeeeeeee/|g' "$binary" 2>/dev/null || true
            fi
          done
        '';
      };

      module = logos-module-builder.lib.mkLogosModule moduleArgs;

      # The same module with the running node simulated (config and key helpers
      # stay real). See mock/README.md; apps take it through mock/flake.nix.
      mockModule = logos-module-builder.lib.mkLogosModule (moduleArgs // {
        tests = null;
        preConfigure = "export LOGOS_BLOCKCHAIN_MOCK=1";
      });

      # Rust client codegen inputs.
      rustSdk = logos-module-builder.inputs.logos-rust-sdk;
      rustSdkRev = rustSdk.rev or "unknown";

      # The logos-protocol semver the builder links.
      protocolVersion =
        let
          header = builtins.readFile
            "${logos-module-builder.inputs.logos-protocol}/cpp/logos_protocol.h";
          parts = builtins.split "LOGOS_PROTOCOL_VERSION_STRING \"([^\"]*)\"" header;
        in
          if builtins.length parts < 2 then "0.1.0"
          else builtins.head (builtins.elemAt parts 1);

      # The client's node crates need rapidsnark, the circuits and the node's
      # toolchain, all taken from the logos-blockchain input.
      mkExampleRustLib = { pkgs, system }:
        let
          nodeFlake = inputs.logos-blockchain;
          rapidsnark = nodeFlake.inputs.rust-rapidsnark.packages.${system}.rapidsnark;
          circuits = nodeFlake.inputs.logos-blockchain-circuits.packages.${system}.default;
          rustChannel =
            (builtins.fromTOML (builtins.readFile "${nodeFlake}/rust-toolchain.toml")).toolchain.channel;
          rpkgs = import nixpkgs {
            inherit system;
            overlays = [ nodeFlake.inputs.rust-overlay.overlays.default ];
          };
          toolchain = rpkgs.rust-bin.stable.${rustChannel}.default;
          rustPlatform = rpkgs.makeRustPlatform { cargo = toolchain; rustc = toolchain; };
        in
        rustPlatform.buildRustPackage {
          pname = "blockchain_client_example";
          version = "0.0.999";
          src = pkgs.runCommand "blockchain-client-example-src" {} ''
            mkdir -p $out
            cp -r ${./rust-client} $out/rust-client
          '';
          sourceRoot = "blockchain-client-example-src/rust-client/example-module/rust-lib";
          cargoLock = {
            lockFile = ./rust-client/example-module/rust-lib/Cargo.lock;
            allowBuiltinFetchGit = true;
          };
          nativeBuildInputs = [ pkgs.pkg-config pkgs.cmake pkgs.clang pkgs.llvmPackages.libclang.lib ];
          buildInputs = [ pkgs.openssl ];
          env = {
            RAPIDSNARK_LIB_DIR = "${rapidsnark}";
            LBC_ROOT_DIR = "${circuits}";
            LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
          };
          doCheck = false;
        };

      mkExampleModule = { pkgs, system }:
        logos-module-builder.lib.mkLogosModule {
          src = ./rust-client/example-module;
          configFile = ./rust-client/example-module/metadata.json;
          flakeInputs = { blockchain_module = self; } // inputs;
          preConfigure = ''
            mkdir -p lib
            cp ${mkExampleRustLib { inherit pkgs system; }}/lib/libblockchain_client_example.a lib/
          '';
        };
    in
    module // {
      mock = mockModule;

      packages = {
        # Windows cross target (x86_64-w64-mingw32) straight from the builder.
        x86_64-windows = module.packages.x86_64-windows;
      } // forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          example = (mkExampleModule { inherit pkgs system; }).packages.${system};
        in
        module.packages.${system}
        // nixpkgs.lib.mapAttrs' (name: nixpkgs.lib.nameValuePair "mock-${name}") mockModule.packages.${system}
        // {
          mock = mockModule.packages.${system}.default;
          rust-client-example = example.default;
          rust-client-example-lgx = example.lgx;
          rust-client-example-lgx-portable = example.lgx-portable;
          rust-client-example-install = example.install;
          rust-client-example-install-portable = example.install-portable;
        });

      # `nix run .#generate` regenerates the .lidl, the client and the example scaffold.
      apps = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          lidlGen = rustSdk.packages.${system}.lidl-gen;
          lidlPkg = module.packages.${system}.lidl;
          generate = pkgs.writeShellApplication {
            name = "blockchain-module-generate";
            runtimeInputs = [ lidlGen pkgs.git pkgs.gnugrep ];
            text = ''
              root="$(git rev-parse --show-toplevel)"

              echo "blockchain_module.lidl <- derived from src/logos_blockchain_module.h"
              install -m 644 "${lidlPkg}/blockchain_module.lidl" "$root/blockchain_module.lidl"

              echo "rust-client/src/generated.rs <- logos-lidl-gen (client backend)"
              logos-lidl-gen "$root/blockchain_module.lidl" \
                -o "$root/rust-client/src/generated.rs"

              echo "rust-client/example-module/rust-lib/src/provider_gen.rs <- logos-lidl-gen --provider (protocol ${protocolVersion})"
              logos-lidl-gen "$root/rust-client/example-module/rust-lib/blockchain_client_example.lidl" \
                --provider --protocol-version "${protocolVersion}" \
                -o "$root/rust-client/example-module/rust-lib/src/provider_gen.rs"

              for manifest in rust-client/Cargo.toml rust-client/example-module/rust-lib/Cargo.toml; do
                if ! grep -q 'rev = "${rustSdkRev}"' "$root/$manifest"; then
                  echo "WARNING: $manifest does not pin logos-rust-sdk rev ${rustSdkRev} (the builder's pin); update it." >&2
                fi
              done
              echo "done."
            '';
          };
        in {
          generate = {
            type = "app";
            program = "${generate}/bin/blockchain-module-generate";
          };
        });
    };
}
