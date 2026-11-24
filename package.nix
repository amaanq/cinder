{
  lib,
  stdenv,
  fetchFromGitea,
  fetchFromGitHub,
  autoPatchelfHook,
  cmake,
  ninja,
  pkg-config,
  ffmpeg-headless,
  rocmPackages,
  hip-clang,
  writeText,
  runCommand,
  llvmPackages,
  gpuTargets ? [ "gfx1201" ],
}:
let
  inherit (stdenv.cc) cc libc;

  # nixpkgs' ROCm 7.2 ships LLVM 22, which spills registers in 674 kernels
  # versus 341 under LLVM 24, and prefill attention runs 1.45x slower.
  # hip-lang's CMake config links with --rtlib=compiler-rt.
  resourceDir = runCommand "radiance-hip-resource-dir" { } ''
    mkdir -p $out/lib/${stdenv.hostPlatform.config}
    ln -s ${hip-clang}/lib/clang/24/include $out/include
    ln -s ${llvmPackages.compiler-rt}/lib/linux/libclang_rt.builtins-x86_64.a \
      $out/lib/${stdenv.hostPlatform.config}/libclang_rt.builtins.a
  '';

  rocmSystems = fetchFromGitHub {
    owner = "ROCm";
    repo = "rocm-systems";
    tag = "therock-10.1";
    sparseCheckout = [
      "projects/hip/include"
      "projects/clr/hipamd/include"
    ];
    hash = "sha256-esRSLaydv+bGg6h+z1DZUK7KA2ayVLtweeLKnj88z/s=";
  };

  # clang 24's HIP wrapper headers do not compile with nixpkgs' HIP 7.2 headers.
  # This root pairs 10.1's HIP headers with nixpkgs' runtime. Both are HIP major 7.
  hipRoot = runCommand "radiance-hip-root" { } /* sh */ ''
    mkdir -p $out/bin $out/include $out/lib/cmake
    cp -r ${rocmSystems}/projects/hip/include/hip $out/include/hip
    chmod -R u+w $out/include
    cp -r ${rocmSystems}/projects/clr/hipamd/include/hip/amd_detail $out/include/hip/

    cat > $out/include/hip/hip_version.h <<EOF
    #ifndef HIP_VERSION_H
    #define HIP_VERSION_H
    #define HIP_VERSION_MAJOR 7
    #define HIP_VERSION_MINOR 16
    #define HIP_VERSION_PATCH 0
    #define HIP_VERSION_GITHASH "0000000"
    #define HIP_VERSION_BUILD_ID 0
    #define HIP_VERSION_BUILD_NAME ""
    #define HIP_VERSION (HIP_VERSION_MAJOR * 10000000 + HIP_VERSION_MINOR * 100000 + HIP_VERSION_PATCH)
    #define __HIP_HAS_GET_PCH 1
    #endif
    EOF
    printf 'HIP_VERSION_MAJOR=7\nHIP_VERSION_MINOR=16\nHIP_VERSION_PATCH=0\n' > $out/bin/.hipVersion

    ln -s ${rocmPackages.clr}/bin/hipcc $out/bin/hipcc
    ln -s ${rocmPackages.clr}/lib/libamdhip64.so* $out/lib/
    cp -rL ${rocmPackages.clr}/lib/cmake/hip-lang $out/lib/cmake/hip-lang
  '';

  hipConfig = writeText "radiance-hip.cfg" ''
    --target=${stdenv.hostPlatform.config}
    -resource-dir=${resourceDir}
    --rocm-path=${hipRoot}
    --hip-path=${hipRoot}
    --rocm-device-lib-path=${hip-clang}/amdgcn/bitcode
    --gcc-install-dir=${cc}/lib/gcc/${stdenv.hostPlatform.config}/${cc.version}
    -idirafter ${lib.getDev libc}/include
    -B${stdenv.cc.bintools}/bin
    -B${libc}/lib
    -L${libc}/lib
    -L${lib.getLib cc}/lib
  '';
in
stdenv.mkDerivation {
  pname = "radiance";
  version = "2.1.0";

  src = fetchFromGitea {
    domain = "codeberg.org";
    owner = "StillDeadcode";
    repo = "radiance";
    rev = "2a2b756371c26f2768b8d129a098df275ace2c73";
    hash = "sha256-Gs/nz5NPChxAdB/0BvmvJ1qfCEwbemE+Ed2qteiThgo=";
  };

  patches = [
    ./patches/drafter-window-snapshot.patch
    ./patches/core-no-offload-compress.patch
    ./patches/xlmroberta.patch
    ./patches/inkling2loop.patch
    ./patches/fleet-cold-metadata.patch
  ];

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    autoPatchelfHook
    hipRoot
  ];

  buildInputs = [
    ffmpeg-headless
    rocmPackages.clr
    rocmPackages.rocm-runtime
  ];

  # CMakeLists.txt derives the HIP include directory from where it finds hipcc.
  env.ROCM_PATH = hipRoot;

  cmakeFlags = [
    (lib.cmakeFeature "RAD_WITH_HIP" "ON")
    (lib.cmakeFeature "RAD_WITH_FFMPEG" "ON")
    (lib.cmakeFeature "RAD_GPU_TARGETS" (lib.concatStringsSep ";" gpuTargets))
    (lib.cmakeFeature "CMAKE_HIP_COMPILER" "${hip-clang}/bin/clang++")
    (lib.cmakeFeature "CMAKE_HIP_COMPILER_ROCM_ROOT" "${hipRoot}")
    (lib.cmakeFeature "CMAKE_HIP_FLAGS" "--config=${hipConfig}")
    (lib.cmakeBool "RAD_HIP_VOPD_REPEATABLE" true)
    (lib.cmakeBool "RAD_BUILD_TESTS" false)
  ];

  meta = {
    description = "Inference server for AMD GPUs in C++ and HIP";
    homepage = "https://codeberg.org/StillDeadcode/radiance";
    license = lib.licenses.asl20;
    mainProgram = "radiance";
    platforms = [ "x86_64-linux" ];
  };
}
