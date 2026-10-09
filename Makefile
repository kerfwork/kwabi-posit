# kwabi-posit: posit<16,1> as a kwabi type body (see README.md).
#
# One library serves PostgreSQL 16, 17 and 18: the body uses no PostgreSQL headers.

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  DLSUFFIX := dylib
else
  DLSUFFIX := so
endif

CXX ?= clang++
UNIVERSAL := third_party/universal
# The library's own headers include both <sw/universal/...> and <universal/...>.
# Universal is C++23 and warns a lot; its headers go in with -isystem.
CXXFLAGS := -std=c++23 -O2 -fPIC -Wall -Wextra
INCLUDES := -Iinclude -isystem $(UNIVERSAL)/include -isystem $(UNIVERSAL)/include/sw

BUILD := build
LIB := $(BUILD)/libkwabi_posit16_1.$(DLSUFFIX)

.PHONY: all lib test clean check-submodule

all: lib

check-submodule:
	@test -f $(UNIVERSAL)/include/sw/universal/number/posit/posit.hpp || \
	  (echo "run: git submodule update --init"; exit 1)

lib: check-submodule $(LIB)

$(LIB): src/posit16_1.cpp include/kwabi.h
	@mkdir -p $(BUILD)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -shared -o $@ src/posit16_1.cpp

test: check-submodule $(BUILD)/body_test
	./$(BUILD)/body_test

$(BUILD)/body_test: tests/body_test.cpp src/posit16_1.cpp include/kwabi.h
	@mkdir -p $(BUILD)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -o $@ tests/body_test.cpp src/posit16_1.cpp

clean:
	rm -rf $(BUILD)
