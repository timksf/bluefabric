{
    description = "BlueFabric development and test environment";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/25.11";
        flake-utils.url = "github:numtide/flake-utils";
    };

    outputs = { flake-utils, nixpkgs, ... }:
        flake-utils.lib.eachSystem ["x86_64-linux"] (system: let
            pkgs = import nixpkgs {
                inherit system;
            };
            python = pkgs.python313;
            cocotbext-axi = python.pkgs.buildPythonPackage rec {
                pname = "cocotbext-axi";
                version = "0.1.28";
                format = "wheel";

                src = pkgs.fetchurl {
                    url = "https://files.pythonhosted.org/packages/29/eb/d1c1f727a52ef2b7d0a2e4ff31817add1ccd42155642ba971b49d9ee089c/cocotbext_axi-${version}-py3-none-any.whl";
                    hash = "sha256-r/iLUocz5OWTWfBrjMMFJMx1vzHulR7YpXNpSyaBbrI=";
                };

                dependencies = with python.pkgs; [
                    cocotb
                    cocotb-bus
                ];
                pythonImportsCheck = ["cocotbext.axi"];
            };
            cocotbext-ahb = python.pkgs.buildPythonPackage rec {
                pname = "cocotbext-ahb";
                version = "0.5.1";
                format = "wheel";

                src = pkgs.fetchurl {
                    url = "https://files.pythonhosted.org/packages/8e/03/9f266d99d6bbaa7388fad1a356eaa44628b0d3e4ec62e46af0f270ba402c/cocotbext_ahb-${version}-py3-none-any.whl";
                    hash = "sha256-XFl7It3gc9LfPXraochukLc32gN7hfPoy6YTSULCn4g=";
                };

                dependencies = with python.pkgs; [
                    cocotb
                    cocotb-bus
                    packaging
                ];
                pythonImportsCheck = ["cocotbext.ahb"];
            };
            python-env = python.withPackages (ps: with ps; [
                cocotb
                cocotb-bus
                packaging
                cocotbext-axi
                cocotbext-ahb
            ]);
        in {
            devShells.default = pkgs.mkShellNoCC {
                packages = with pkgs; [
                    bluespec
                    gnumake
                    iverilog
                    python-env
                ];
                LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
                    pkgs.stdenv.cc.cc.lib
                ];
            };
        });
}
