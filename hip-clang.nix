{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  python3,
  zlib,
  zstd,
}:
stdenv.mkDerivation {
  pname = "radiance-hip-clang";
  version = "24.0.0-rocm-10.1";

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "llvm-project";
    rev = "d6f6cb691863e9258034ab48c1dfce21689d5606";
    hash = "sha256-WkgJF0D4XsrWKbJO+vKow9CrNIKL/PqOXRwrB3ECsQE=";
  };

  # Without this, LLVM 24 pairs VOPD instructions differently from compile to
  # compile, so radiance turns pairing off for an unpatched compiler.
  patches = [ ./patches/llvm-vopd-pairing.patch ];

  nativeBuildInputs = [
    cmake
    ninja
    python3
  ];

  buildInputs = [
    zlib
    zstd
  ];

  cmakeDir = "../llvm";

  preConfigure = ''
    cmakeFlagsArray+=("-DLLVM_EXTERNAL_DEVICE_LIBS_SOURCE_DIR=$PWD/amd/device-libs")
  '';

  cmakeFlags = [
    (lib.cmakeFeature "LLVM_ENABLE_PROJECTS" "clang;lld")
    (lib.cmakeFeature "LLVM_TARGETS_TO_BUILD" "AMDGPU;X86")
    (lib.cmakeFeature "LLVM_EXTERNAL_PROJECTS" "device-libs")
    (lib.cmakeBool "LLVM_ENABLE_ASSERTIONS" false)
    (lib.cmakeBool "LLVM_INCLUDE_TESTS" false)
    (lib.cmakeBool "LLVM_INCLUDE_BENCHMARKS" false)
    (lib.cmakeBool "LLVM_INCLUDE_EXAMPLES" false)
    (lib.cmakeBool "LLVM_INCLUDE_DOCS" false)
    (lib.cmakeBool "CLANG_INCLUDE_TESTS" false)
    (lib.cmakeBool "CLANG_ENABLE_STATIC_ANALYZER" false)
    (lib.cmakeBool "CLANG_ENABLE_ARCMT" false)
    (lib.cmakeFeature "LLVM_FORCE_VC_REVISION" "d6f6cb691863e9258034ab48c1dfce21689d5606")
    (lib.cmakeFeature "LLVM_FORCE_VC_REPOSITORY" "https://github.com/ROCm/llvm-project.git")
  ];

  meta = {
    description = "ROCm 10.1's clang, built to compile radiance's device kernels";
    homepage = "https://github.com/ROCm/llvm-project";
    license = with lib.licenses; [
      asl20
      llvm-exception
    ];
    platforms = [ "x86_64-linux" ];
  };
}
