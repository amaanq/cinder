{
  lib,
  stdenv,
  fetchFromGitea,
  cmake,
  ninja,
  pkg-config,
  ffmpeg-headless,
  rocmPackages,
  gpuTargets ? [ "gfx1201" ],
}:
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
  ];

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    rocmPackages.clr
  ];

  buildInputs = [
    ffmpeg-headless
    rocmPackages.clr
    rocmPackages.rocm-runtime
  ];

  # CMakeLists.txt derives the HIP include directory from where it finds hipcc.
  env.ROCM_PATH = rocmPackages.clr;

  cmakeFlags = [
    (lib.cmakeFeature "RAD_WITH_HIP" "ON")
    (lib.cmakeFeature "RAD_WITH_FFMPEG" "ON")
    (lib.cmakeFeature "RAD_GPU_TARGETS" (lib.concatStringsSep ";" gpuTargets))
    (lib.cmakeFeature "CMAKE_HIP_COMPILER" "${rocmPackages.clr.hipClangPath}/clang++")
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
