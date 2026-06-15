#!/bin/bash

# this script runs the unit testbenches
# script structure adapted from EIE Y2 RISC-V project in autumn term
# usage: ./doit.sh <testname1> <testname2>

# constants
SCRIPT_DIR=$(dirname "$(realpath "$0")")
RTL_FOLDER=$(realpath "$SCRIPT_DIR/../overlay/ip/pixel_generator_1.0")
TEST_FOLDER=$(realpath "$SCRIPT_DIR/unit_tests")
GREEN=$(tput setaf 2 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

# test registry
# format: test_name:rtl_file:testbench_file:extra_verilator_args
TESTS=(
    "object_laplacian:$RTL_FOLDER/laplacian.v:$TEST_FOLDER/object_laplacian_tb.cpp:"
    "object_classification:$RTL_FOLDER/object_classification.v:$TEST_FOLDER/object_classification_tb.cpp:"
    "apply_damping:$RTL_FOLDER/apply_damping.v:$TEST_FOLDER/apply_damping_tb.cpp:-GPRESS_W=18"
    "boundary_damping_coeff:$RTL_FOLDER/boundary_damping_coeff.v:$TEST_FOLDER/boundary_damping_coeff_tb.cpp:-GWIDTH=320 -GHEIGHT=240"
    "pixel_generator:$RTL_FOLDER/pixel_generator.v:$TEST_FOLDER/pixel_generator_tb.cpp:$RTL_FOLDER/laplacian.v $RTL_FOLDER/object_classification.v $RTL_FOLDER/apply_damping.v $RTL_FOLDER/boundary_damping_coeff.v -Wno-PROCASSINIT -Wno-VARHIDDEN"
)

# variables
passes=0
fails=0

# dependency paths
if [[ -z "${GTEST_ROOT:-}" ]]; then
    if [[ -d /opt/homebrew/Cellar/googletest/1.17.0 ]]; then
        GTEST_ROOT="/opt/homebrew/Cellar/googletest/1.17.0"
    elif command -v brew >/dev/null 2>&1; then
        GTEST_ROOT="$(brew --prefix googletest)"
    else
        echo "error: googletest not found, install it or set GTEST_ROOT" >&2
        exit 1
    fi
fi

CXX_SYSROOT_FLAGS=""
if command -v xcrun >/dev/null 2>&1; then
    SDK_ROOT="$(xcrun --show-sdk-path)"
    if [[ -d "$SDK_ROOT/usr/include/c++/v1" ]]; then
        CXX_SYSROOT_FLAGS="-isysroot $SDK_ROOT -isystem $SDK_ROOT/usr/include/c++/v1"
    fi
fi

list_tests() {
    for test_spec in "${TESTS[@]}"; do
        IFS=":" read -r name _ _ _ <<< "$test_spec"
        echo "$name"
    done
}

find_test() {
    local target="$1"

    for test_spec in "${TESTS[@]}"; do
        IFS=":" read -r name rtl_file tb_file verilator_args <<< "$test_spec"
        if [[ "$name" == "$target" ]]; then
            echo "$rtl_file:$tb_file:$verilator_args"
            return 0
        fi
    done

    return 1
}

# handle terminal arguments
if [[ "$1" == "list" ]]; then
    list_tests
    exit 0
fi

if [[ $# -eq 0 || "$1" == "all" ]]; then
    # if no arguments provided, run all tests
    files=()
    for test_spec in "${TESTS[@]}"; do
        IFS=":" read -r name _ _ _ <<< "$test_spec"
        files+=("$name")
    done
else
    # if arguments provided, use them as test names
    files=("$@")
fi

cd "$SCRIPT_DIR"

# iterate through tests
for file in "${files[@]}"; do
    name="$file"

    test_files=$(find_test "$name")
    if [[ $? -ne 0 ]]; then
        echo "${RED}error: unknown unit test '$name'${RESET}" >&2
        echo "available tests:" >&2
        list_tests >&2
        exit 1
    fi

    IFS=":" read -r rtl_file tb_file verilator_args <<< "$test_files"

    echo "running $name"
    rm -rf obj_dir

    if [[ "$name" == "boundary_damping_coeff" ]]; then
        head -n 24 "$RTL_FOLDER/damping_lut_q8.mem" > "$SCRIPT_DIR/damping_lut_q8.mem"
    elif [[ "$name" == "pixel_generator" ]]; then
        head -n 24 "$RTL_FOLDER/damping_lut_q8.mem" > "$SCRIPT_DIR/damping_lut_q8.mem"
    fi

    # translate verilog to c++ including testbench
    verilator -Wall --trace \
        -Wno-DECLFILENAME \
        -Wno-WIDTHEXPAND \
        -Wno-WIDTHTRUNC \
        -Wno-UNUSEDSIGNAL \
        $verilator_args \
        -cc "$rtl_file" \
        --exe "$tb_file" \
        --prefix "Vdut" \
        -o Vdut \
        -CFLAGS "$CXX_SYSROOT_FLAGS -I$TEST_FOLDER -isystem $GTEST_ROOT/include" \
        -LDFLAGS "-L$GTEST_ROOT/lib -lgtest -lgtest_main -lpthread"

    verilator_status=$?

    if [[ $verilator_status -eq 0 ]]; then
        # build c++ project with automatically generated makefile
        make -j -C obj_dir/ -f Vdut.mk
        make_status=$?
    else
        make_status=1
    fi

    if [[ $verilator_status -eq 0 && $make_status -eq 0 ]]; then
        # run executable simulation file
        ./obj_dir/Vdut
        run_status=$?
    else
        run_status=1
    fi

    # check if the test succeeded or not
    if [[ $verilator_status -eq 0 && $make_status -eq 0 && $run_status -eq 0 ]]; then
        ((passes++))
    else
        ((fails++))
    fi
done

# exit as a pass or fail
if [[ $fails -eq 0 ]]; then
    echo "${GREEN}success: all ${passes} test(s) passed${RESET}"
    exit 0
else
    total=$((passes + fails))
    echo "${RED}failure: only ${passes} test(s) passed out of ${total}${RESET}"
    exit 1
fi
