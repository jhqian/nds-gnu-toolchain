#!/bin/bash

# macOS version of build_elf_toolchain.sh
# This script builds a RISC-V 32-bit ELF toolchain on macOS

set -e  # Exit on error

# Progress tracking
STEP=0
TOTAL_STEPS=9

print_step() {
    STEP=$((STEP + 1))
    echo ""
    echo "================================================================================"
    echo "[$STEP/$TOTAL_STEPS] $1"
    echo "================================================================================"
    echo ""
}

print_substep() {
    echo ">>> $1"
}

TARGET=riscv32-elf
PREFIX=$HOME/toolchains/nds32le-elf-newlib-v5
ARCH=rv32imc_zicsr_zifencei_xandes
ABI=ilp32
CPU=andes-25-series
MULTILIB=dsp,zc,andes45
# Multilib generator format: ARCH-ABI-ALT_ARCHS-EXTENSIONS
# Format: <arch>-<abi>-<extra>-<ext>
# Note: Even if extra and ext are empty, must use -- as placeholder
# Example: rv32imac-ilp32-- (correct) vs rv32imac-ilp32 (wrong)
# Andes-specific multilibs
MULTILIB_GENERATOR="${ARCH}-${ABI}--;rv32imfc_zicsr_zifencei_xandes-ilp32--;rv32imfc_zicsr_zifencei_xandes-ilp32f--;rv32imfdc_zicsr_zifencei_xandes-ilp32d--;rv32imfdc_zicsr_zifencei_xandes-ilp32f--;rv32imfdc_zicsr_zifencei_xandes-ilp32--;rv32imafc_zicsr_zifencei_xandes-ilp32--;rv32imafc_zicsr_zifencei_xandes-ilp32f--;rv32imafdc_zicsr_zifencei_xandes-ilp32d--;rv32imafdc_zicsr_zifencei_xandes-ilp32f--;rv32imafdc_zicsr_zifencei_xandes-ilp32--"
BUILD=`pwd`/build-nds32le-elf-newlib-v5

BINUTILS_SRC=`pwd`/binutils
GCC_SRC=`pwd`/gcc
NEWLIB_SRC=`pwd`/newlib
WRAPPER_SRC=`pwd`/compiler-wrapper

# macOS uses sysctl instead of nproc
if command -v nproc > /dev/null 2>&1; then
    MAKE_PARALLEL=-j`nproc`
elif command -v sysctl > /dev/null 2>&1; then
    MAKE_PARALLEL=-j`sysctl -n hw.ncpu`
else
    MAKE_PARALLEL=-j4  # Fallback to 4 cores
fi
#MAKE_PARALLEL=-j1  # Uncomment for single-threaded build

# Print header
echo "================================================================================"
echo "RISC-V 32-bit ELF Toolchain Build Script for macOS"
echo "================================================================================"
echo ""
echo "Configuration:"
echo "  Target:     ${TARGET}"
echo "  Prefix:     ${PREFIX}"
echo "  Arch:       ${ARCH}"
echo "  ABI:        ${ABI}"
echo "  CPU:        ${CPU}"
echo "  Multilib:   ${MULTILIB}"
echo "  Build Dir:  ${BUILD}"
echo "  Parallel:   ${MAKE_PARALLEL}"
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Warning: This script is designed for macOS. You are running on $OSTYPE"
fi

# Check for required dependencies
print_step "Checking Dependencies"
missing_deps=()

if ! command -v make > /dev/null 2>&1; then
    missing_deps+=("make")
fi

if ! command -v gcc > /dev/null 2>&1 && ! command -v clang > /dev/null 2>&1; then
    missing_deps+=("gcc or clang")
fi

if ! command -v python3 > /dev/null 2>&1; then
    missing_deps+=("python3")
fi

if [ ${#missing_deps[@]} -ne 0 ]; then
    echo "✗ Missing dependencies: ${missing_deps[*]}"
    echo "Please install them using Homebrew: brew install ${missing_deps[*]}"
    echo "Or install Xcode Command Line Tools: xcode-select --install"
    exit 1
fi
echo "✓ All dependencies found"
echo ""

# Check if PREFIX has changed and clean build directory if needed
if [ -d "${BUILD}" ]; then
    PREFIX_FILE="${BUILD}/.configured_prefix"
    if [ -f "${PREFIX_FILE}" ]; then
        OLD_PREFIX=$(cat "${PREFIX_FILE}")
        if [ "${OLD_PREFIX}" != "${PREFIX}" ]; then
            echo "⚠ Warning: PREFIX has changed from ${OLD_PREFIX} to ${PREFIX}"
            echo "⚠ Cleaning build directory to avoid configuration conflicts..."
            rm -rf "${BUILD}"
            mkdir -p "${BUILD}"
        fi
    fi
fi

mkdir -p ${BUILD}
# Save current PREFIX for future checks
echo "${PREFIX}" > "${BUILD}/.configured_prefix"

# 00. Prepare
print_step "Preparing Build Environment"
print_substep "Setting up PATH"
export PATH=${PREFIX}/bin:$PATH

print_substep "Downloading GCC prerequisites (this may take a while)..."
cd ${GCC_SRC}
./contrib/download_prerequisites
cd -
echo "✓ GCC prerequisites downloaded"

cd ${BUILD}
# 01. Binutils
print_step "Building Binutils"
mkdir -p binutils
cd binutils

print_substep "Configuring Binutils..."
${BINUTILS_SRC}/configure \
  --target=${TARGET} --prefix=${PREFIX} --with-arch=${ARCH} \
  --with-curses --disable-nls --disable-tui --with-python=no --with-lzma=no \
  --with-expat=yes --with-guile=no --enable-plugins --disable-werror \
  --enable-deterministic-archives --disable-gdb --disable-sim \
  --enable-multilib=yes --with-multilib-list=${MULTILIB}
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Binutils configuration completed"

print_substep "Building Binutils (this may take a while)..."
make ${MAKE_PARALLEL} all
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Binutils build completed"

print_substep "Installing Binutils..."
make install
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Binutils installation completed"

cd ..

# 02. Bootstrap GCC
print_step "Building Bootstrap GCC (C only)"
mkdir -p bootstrap-gcc
cd bootstrap-gcc

print_substep "Configuring Bootstrap GCC..."
${GCC_SRC}/configure \
  --prefix=${PREFIX} --with-arch=${ARCH} --with-tune=${CPU} --target=${TARGET} \
  --disable-nls --enable-languages=c --enable-lto \
  --enable-Os-default-ex9=yes --enable-gp-insn-relax-default=yes \
  --enable-error-on-no-atomic=yes --disable-tls \
  --enable-multilib=yes --with-multilib-generator="${MULTILIB_GENERATOR}" \
  --with-newlib --with-abi=${ABI} --disable-werror \
  --disable-shared --enable-threads=single \
  --enable-checking=release \
  CFLAGS_FOR_TARGET="-O2 -g -mstrict-align" \
  CXXFLAGS_FOR_TARGET="-O2 -g -mstrict-align"
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Bootstrap GCC configuration completed"

print_substep "Building Bootstrap GCC (this may take a while)..."
make ${MAKE_PARALLEL} all-gcc
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Bootstrap GCC build completed"

print_substep "Installing Bootstrap GCC..."
make install-gcc
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Bootstrap GCC installation completed"

cd ..

# 03. Newlib
print_step "Building Newlib"
mkdir -p newlib
cd newlib

print_substep "Configuring Newlib..."
${NEWLIB_SRC}/configure --prefix=${PREFIX} --target=${TARGET} \
  CFLAGS_FOR_TARGET="-O2 -ffunction-sections -fdata-sections -mstrict-align"
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Newlib configuration completed"

print_substep "Building Newlib (this may take a while)..."
make ${MAKE_PARALLEL} all
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Newlib build completed"

print_substep "Installing Newlib..."
make install
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Newlib installation completed"

cd ..

# 03b. Newlib-nano
print_step "Building Newlib-nano"
mkdir -p newlib-nano
cd newlib-nano

print_substep "Configuring Newlib-nano..."
${NEWLIB_SRC}/configure --prefix=${PREFIX} --target=${TARGET} \
  --enable-newlib-nano-malloc \
  --enable-newlib-nano-formatted-io \
  CFLAGS_FOR_TARGET="-Os -ffunction-sections -fdata-sections -mstrict-align"
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Newlib-nano configuration completed"

print_substep "Building Newlib-nano (this may take a while)..."
make ${MAKE_PARALLEL} all
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Newlib-nano build completed"

print_substep "Backing up standard newlib libraries before installing nano..."
# Backup standard libraries before nano installation overwrites them
BACKUP_DIR="${BUILD}/newlib-std-backup"
mkdir -p "${BACKUP_DIR}"
find ${PREFIX}/${TARGET}/lib -name "libc.a" -o -name "libm.a" -o -name "libg.a" -o -name "libgloss.a" | while read lib; do
    if [ -f "$lib" ]; then
        rel_path=$(echo "$lib" | sed "s|${PREFIX}/${TARGET}/lib/||")
        backup_path="${BACKUP_DIR}/${rel_path}"
        mkdir -p "$(dirname "$backup_path")"
        cp "$lib" "$backup_path"
    fi
done
echo "✓ Standard libraries backed up"

print_substep "Installing Newlib-nano..."
make install
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Newlib-nano installation completed"

print_substep "Renaming nano libraries to *_nano.a and restoring standard libraries..."
# Rename newly installed nano libraries and restore standard ones
find ${PREFIX}/${TARGET}/lib -name "libc.a" -type f | while read lib; do
    dir=$(dirname "$lib")
    rel_path=$(echo "$lib" | sed "s|${PREFIX}/${TARGET}/lib/||")
    backup_path="${BACKUP_DIR}/${rel_path}"
    
    if [ -f "$lib" ]; then
        # Rename nano library
        mv "$lib" "$dir/libc_nano.a"
        echo "  Renamed: $lib -> $dir/libc_nano.a"
        
        # Restore standard library if backup exists
        if [ -f "$backup_path" ]; then
            cp "$backup_path" "$lib"
            echo "  Restored: $lib"
        fi
    fi
done

find ${PREFIX}/${TARGET}/lib -name "libm.a" -type f | while read lib; do
    dir=$(dirname "$lib")
    rel_path=$(echo "$lib" | sed "s|${PREFIX}/${TARGET}/lib/||")
    backup_path="${BACKUP_DIR}/${rel_path}"
    
    if [ -f "$lib" ]; then
        mv "$lib" "$dir/libm_nano.a"
        echo "  Renamed: $lib -> $dir/libm_nano.a"
        if [ -f "$backup_path" ]; then
            cp "$backup_path" "$lib"
            echo "  Restored: $lib"
        fi
    fi
done

find ${PREFIX}/${TARGET}/lib -name "libg.a" -type f | while read lib; do
    dir=$(dirname "$lib")
    rel_path=$(echo "$lib" | sed "s|${PREFIX}/${TARGET}/lib/||")
    backup_path="${BACKUP_DIR}/${rel_path}"
    
    if [ -f "$lib" ]; then
        mv "$lib" "$dir/libg_nano.a"
        echo "  Renamed: $lib -> $dir/libg_nano.a"
        if [ -f "$backup_path" ]; then
            cp "$backup_path" "$lib"
            echo "  Restored: $lib"
        fi
    fi
done

find ${PREFIX}/${TARGET}/lib -name "libgloss.a" -type f | while read lib; do
    dir=$(dirname "$lib")
    rel_path=$(echo "$lib" | sed "s|${PREFIX}/${TARGET}/lib/||")
    backup_path="${BACKUP_DIR}/${rel_path}"
    
    if [ -f "$lib" ]; then
        mv "$lib" "$dir/libgloss_nano.a"
        echo "  Renamed: $lib -> $dir/libgloss_nano.a"
        if [ -f "$backup_path" ]; then
            cp "$backup_path" "$lib"
            echo "  Restored: $lib"
        fi
    fi
done

echo "✓ Nano libraries renamed and standard libraries restored"

cd ..
# 04. Final GCC
print_step "Building Final GCC (C and C++)"
mkdir -p final-gcc
cd final-gcc

print_substep "Configuring Final GCC..."
${GCC_SRC}/configure \
  --prefix=${PREFIX} --with-arch=${ARCH} --with-tune=${CPU} --target=${TARGET} \
  --disable-nls --enable-languages=c,c++ --enable-lto --with-abi=${ABI} \
  --enable-Os-default-ex9=yes --enable-gp-insn-relax-default=yes \
  --enable-error-on-no-atomic=yes --disable-tls \
  --enable-multilib=yes --with-multilib-generator="${MULTILIB_GENERATOR}" \
  --with-newlib --disable-shared --enable-threads=single \
  --disable-werror --with-headers=${PREFIX}/${TARGET}/include \
  --enable-checking=release \
  CFLAGS_FOR_TARGET="-O2 -g -mstrict-align" \
  CXXFLAGS_FOR_TARGET="-O2 -g -mstrict-align"
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Final GCC configuration completed"

print_substep "Building Final GCC (this may take a while)..."
make ${MAKE_PARALLEL} all
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Final GCC build completed"

print_substep "Installing Final GCC..."
make install
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ Final GCC installation completed"

cd ..

# 5. GDB
print_step "Building GDB"
mkdir -p gdb
cd gdb

print_substep "Configuring GDB..."
${BINUTILS_SRC}/configure \
  --target=${TARGET} --prefix=${PREFIX} --with-arch=${ARCH} \
  --with-curses --disable-nls --enable-tui --with-python=no \
  --with-lzma=no --with-expat=yes --with-guile=no \
  --disable-werror --disable-sim \
  --disable-binutils --disable-ld --disable-gas --disable-gprof
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ GDB configuration completed"

print_substep "Building GDB (this may take a while)..."
make ${MAKE_PARALLEL} all
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ GDB build completed"

print_substep "Installing GDB..."
make install
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
echo "✓ GDB installation completed"

cd ..

# 6. build compiler wrapper
print_step "Building Compiler Wrapper"
print_substep "Renaming original compilers..."
mv -v ${PREFIX}/bin/${TARGET}-gcc \
        ${PREFIX}/bin/${TARGET}-gcc.gnu
mv -v ${PREFIX}/bin/${TARGET}-g++ \
        ${PREFIX}/bin/${TARGET}-g++.gnu
mv -v ${PREFIX}/bin/${TARGET}-c++ \
        ${PREFIX}/bin/${TARGET}-c++.gnu
echo "✓ Original compilers renamed"

# Check if compiler-wrapper submodule needs to be initialized
print_substep "Checking compiler-wrapper submodule..."
SKIP_WRAPPER=false
if [ ! -f "${WRAPPER_SRC}/configure" ] && [ ! -f "${WRAPPER_SRC}/configure.ac" ]; then
    echo "Compiler-wrapper submodule appears to be empty. Attempting to initialize..."
    if command -v git > /dev/null 2>&1; then
        # Check if directory is truly empty (only .git file exists)
        FILE_COUNT=$(find "${WRAPPER_SRC}" -mindepth 1 -maxdepth 1 ! -name '.git' 2>/dev/null | wc -l | tr -d ' ')
        SUBMODULE_STATUS=$(git submodule status compiler-wrapper 2>/dev/null | head -1)
        
        if [ "$FILE_COUNT" -eq 0 ] && [ -n "$SUBMODULE_STATUS" ] && ! echo "$SUBMODULE_STATUS" | grep -q "^\-"; then
            # Submodule is registered but content not checked out - force update
            echo "Submodule registered but content missing, forcing checkout..."
            (cd "${WRAPPER_SRC}" && git checkout -f HEAD 2>&1) || {
                echo "Attempting to update submodule from parent repository..."
                git submodule update --init --force compiler-wrapper 2>&1 || {
                    echo "⚠ Warning: Failed to force update compiler-wrapper submodule"
                    echo "⚠ Trying alternative method: removing and re-initializing..."
                    rm -rf "${WRAPPER_SRC}"
                    git submodule update --init compiler-wrapper 2>&1 || {
                        echo "⚠ Warning: Failed to re-initialize compiler-wrapper submodule"
                        echo "⚠ Skipping compiler-wrapper build. Toolchain will work without wrapper."
                        SKIP_WRAPPER=true
                    }
                }
            }
        elif echo "$SUBMODULE_STATUS" | grep -q "^\-"; then
            # Submodule is registered but not initialized
            echo "Initializing compiler-wrapper submodule..."
            git submodule update --init compiler-wrapper 2>&1 || {
                echo "⚠ Warning: Failed to initialize compiler-wrapper submodule"
                echo "⚠ Skipping compiler-wrapper build. Toolchain will work without wrapper."
                SKIP_WRAPPER=true
            }
        elif [ -z "$SUBMODULE_STATUS" ]; then
            # Submodule status not found, try to init all
            echo "Submodule status unclear, attempting to initialize all submodules..."
            git submodule update --init 2>&1 || {
                echo "⚠ Warning: Failed to initialize submodules"
                echo "⚠ Skipping compiler-wrapper build. Toolchain will work without wrapper."
                SKIP_WRAPPER=true
            }
        else
            # Try regular update
            echo "Attempting to update compiler-wrapper submodule..."
            git submodule update --init compiler-wrapper 2>&1 || {
                echo "⚠ Warning: Failed to update compiler-wrapper submodule"
                echo "⚠ Skipping compiler-wrapper build. Toolchain will work without wrapper."
                SKIP_WRAPPER=true
            }
        fi
    else
        echo "⚠ Warning: git not found, cannot initialize submodule"
        echo "⚠ Skipping compiler-wrapper build. Toolchain will work without wrapper."
        SKIP_WRAPPER=true
    fi
    # Re-check after initialization attempt
    if [ "${SKIP_WRAPPER}" != "true" ] && [ ! -f "${WRAPPER_SRC}/configure" ] && [ ! -f "${WRAPPER_SRC}/configure.ac" ]; then
        echo "⚠ Warning: compiler-wrapper still empty after initialization attempt"
        echo "⚠ Manual initialization may be needed. Try one of these commands:"
        echo "⚠   1. cd $(dirname ${WRAPPER_SRC}) && git submodule update --init --force compiler-wrapper"
        echo "⚠   2. cd $(dirname ${WRAPPER_SRC}) && rm -rf compiler-wrapper && git submodule update --init compiler-wrapper"
        echo "⚠   3. cd $(dirname ${WRAPPER_SRC}) && cd compiler-wrapper && git checkout -f HEAD"
        echo "⚠ Skipping compiler-wrapper build. Toolchain will work without wrapper."
        SKIP_WRAPPER=true
    fi
fi

if [ "${SKIP_WRAPPER}" != "true" ] && [ -f "${WRAPPER_SRC}/configure" ]; then
    mkdir -p compiler-wrapper
    cd compiler-wrapper

    print_substep "Configuring Compiler Wrapper..."
    ${WRAPPER_SRC}/configure \
        --prefix=${PREFIX}\
        --target=${TARGET} \
        --compiler-wrapper=gcc-wrapper \
        --with-multilib-list=${MULTILIB} \
        --with-arch=${ARCH} \
        --with-abi=${ABI} \
        --with-libc=newlib \
        --with-sysroot=${PREFIX}/${TARGET}
    rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
    echo "✓ Compiler Wrapper configuration completed"

    print_substep "Building Compiler Wrapper..."
    make ${MAKE_PARALLEL} all
    rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
    echo "✓ Compiler Wrapper build completed"

    print_substep "Installing Compiler Wrapper..."
    make install
    rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
    echo "✓ Compiler Wrapper installation completed"

    cd ..
elif [ "${SKIP_WRAPPER}" != "true" ]; then
    echo "⚠ Warning: compiler-wrapper configure script not found"
    echo "⚠ Skipping compiler-wrapper build. Toolchain will work without wrapper."
fi

# Final summary
echo ""
echo "================================================================================"
echo "Build Completed Successfully!"
echo "================================================================================"
echo ""
echo "Toolchain installed to: ${PREFIX}"
echo ""
echo "To use the toolchain, add to your PATH:"
echo "  export PATH=${PREFIX}/bin:\$PATH"
echo ""
echo "Available tools:"
echo "  ${TARGET}-gcc"
echo "  ${TARGET}-g++"
echo "  ${TARGET}-objdump"
echo "  ${TARGET}-objcopy"
echo "  ${TARGET}-gdb"
echo ""
