// posit16_1 — a kwabi type body for posit<16,1> (Universal, third_party/universal).
//
// The runtime calls these functions; they never raise, and they never let a C++ exception
// cross into the runtime. A value travels as its 16-bit encoding, zero-extended to 64 bits.
//
// Semantics, chosen for this type and documented in README.md:
//   - input: plain decimal only. Out-of-range values saturate to maxpos, which is how
//     posits behave, and are not an error.
//   - output: the shortest decimal that reads back to the same encoding. NaR prints as "NaR".
//   - arithmetic: a division by zero is 22012; an operation that yields NaR is 22003.
//   - mod is not defined for posits: 0A000 (feature_not_supported).
//   - comparisons: NaR is equal only to NaR and greater than every other value, so the
//     btree order is total.

#include <sw/universal/number/posit/posit.hpp>

#include "kwabi.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

namespace {

using Posit = sw::universal::posit<16, 1>;

// PostgreSQL SQLSTATE encoding, as in kwabi's other bodies.
constexpr int six(char ch) { return (ch - '0') & 0x3F; }
constexpr int sqlstate(const char (&c)[6]) {
    return six(c[0]) | (six(c[1]) << 6) | (six(c[2]) << 12) | (six(c[3]) << 18) | (six(c[4]) << 24);
}
constexpr int SQLSTATE_INVALID_TEXT = sqlstate("22P02");
constexpr int SQLSTATE_OUT_OF_RANGE = sqlstate("22003");
constexpr int SQLSTATE_DIVISION_BY_ZERO = sqlstate("22012");
constexpr int SQLSTATE_NOT_SUPPORTED = sqlstate("0A000");

void fail(KwabiError* err, int sqlerrcode, const char* message) {
    kwabi_error_init(err);
    kwabi_error_set_core(err, sqlerrcode, KWABI_ERR_BODY_RAISED, message);
}

// Plain decimal: [-] digits [. digits] [e [+-] digits], with at least one digit in the
// mantissa. Anything else (signs on exponents, spaces, hex, inf, nan) is rejected here,
// so strtod's wider grammar never reaches the user.
bool parse_decimal(const char* s, double& out) {
    const char* p = s;
    if (*p == '-') ++p;
    int mantissa_digits = 0;
    while (*p >= '0' && *p <= '9') { ++p; ++mantissa_digits; }
    if (*p == '.') {
        ++p;
        while (*p >= '0' && *p <= '9') { ++p; ++mantissa_digits; }
    }
    if (mantissa_digits == 0) return false;
    if (*p == 'e' || *p == 'E') {
        ++p;
        if (*p == '+' || *p == '-') ++p;
        int exp_digits = 0;
        while (*p >= '0' && *p <= '9') { ++p; ++exp_digits; }
        if (exp_digits == 0) return false;
    }
    if (*p != '\0') return false;
    out = std::strtod(s, nullptr);
    return true;
}

Posit from_encoding(uint64_t bits) {
    Posit p;
    p.setbits(bits & 0xFFFFull);
    return p;
}

// The shortest decimal that reads back to the same posit.
std::string format_posit(const Posit& p) {
    if (p.isnar()) return "NaR";
    char buf[40];
    for (int precision = 1; precision <= 17; ++precision) {
        std::snprintf(buf, sizeof buf, "%.*g", precision, static_cast<double>(p));
        double back = 0;
        if (parse_decimal(buf, back) && Posit(back).encoding() == p.encoding()) return buf;
    }
    std::snprintf(buf, sizeof buf, "%.17g", static_cast<double>(p));
    return buf;
}

}  // namespace

extern "C" {

static KwabiStatus posit_input(const char* text, uint64_t* value, KwabiError* err, void*) {
    try {
        double v = 0;
        if (!parse_decimal(text, v)) {
            fail(err, SQLSTATE_INVALID_TEXT, "invalid input syntax for type posit16_1");
            return KWABI_ERR_BODY_RAISED;
        }
        *value = Posit(v).encoding();
        return KWABI_OK;
    } catch (...) {
        fail(err, SQLSTATE_INVALID_TEXT, "internal error reading posit16_1");
        return KWABI_ERR_BODY_RAISED;
    }
}

static KwabiStatus posit_output(uint64_t value, char* buf, size_t buflen, KwabiError* err, void*) {
    try {
        std::string s = format_posit(from_encoding(value));
        if (s.size() + 1 > buflen) {
            kwabi_error_init(err);
            kwabi_error_set_core(err, 0, KWABI_ERR_BAD_ARG, "output buffer too small");
            return KWABI_ERR_BAD_ARG;
        }
        std::memcpy(buf, s.c_str(), s.size() + 1);
        return KWABI_OK;
    } catch (...) {
        fail(err, 0, "internal error writing posit16_1");
        return KWABI_ERR_BODY_RAISED;
    }
}

static KwabiStatus posit_binop(uint32_t op, uint64_t a, uint64_t b, uint64_t* result,
                               KwabiError* err, void*) {
    try {
        const Posit x = from_encoding(a), y = from_encoding(b);
        bool x_nar = x.isnar(), y_nar = y.isnar();

        // Comparisons. NaR is equal to NaR and above every other value.
        auto cmp_order = [&]() -> uint64_t {
            if (x_nar || y_nar) return x_nar && y_nar ? KWABI_TYPE_ORDER_EQUAL
                                     : x_nar ? KWABI_TYPE_ORDER_GREATER : KWABI_TYPE_ORDER_LESS;
            if (x < y) return KWABI_TYPE_ORDER_LESS;
            if (x == y) return KWABI_TYPE_ORDER_EQUAL;
            return KWABI_TYPE_ORDER_GREATER;
        };
        switch (op) {
            case KWABI_TYPE_OP_EQ: *result = (x_nar && y_nar) || (!x_nar && !y_nar && x == y); return KWABI_OK;
            case KWABI_TYPE_OP_NE: *result = !((x_nar && y_nar) || (!x_nar && !y_nar && x == y)); return KWABI_OK;
            case KWABI_TYPE_OP_LT: *result = cmp_order() == KWABI_TYPE_ORDER_LESS; return KWABI_OK;
            case KWABI_TYPE_OP_LE: *result = cmp_order() != KWABI_TYPE_ORDER_GREATER; return KWABI_OK;
            case KWABI_TYPE_OP_GT: *result = cmp_order() == KWABI_TYPE_ORDER_GREATER; return KWABI_OK;
            case KWABI_TYPE_OP_GE: *result = cmp_order() != KWABI_TYPE_ORDER_LESS; return KWABI_OK;
            case KWABI_TYPE_OP_ORDER: *result = cmp_order(); return KWABI_OK;
            default: break;
        }

        // Arithmetic. NaR operands give NaR, which is an error at the SQL level.
        Posit r;
        switch (op) {
            case KWABI_TYPE_OP_ADD: r = x + y; break;
            case KWABI_TYPE_OP_SUB: r = x - y; break;
            case KWABI_TYPE_OP_MUL: r = x * y; break;
            case KWABI_TYPE_OP_DIV:
                if (y.iszero()) {
                    fail(err, SQLSTATE_DIVISION_BY_ZERO, "division by zero");
                    return KWABI_ERR_BODY_RAISED;
                }
                r = x / y;
                break;
            case KWABI_TYPE_OP_MOD:
                fail(err, SQLSTATE_NOT_SUPPORTED, "modulo is not defined for posit16_1");
                return KWABI_ERR_BODY_RAISED;
            default:
                fail(err, SQLSTATE_NOT_SUPPORTED, "unknown operator for posit16_1");
                return KWABI_ERR_BODY_RAISED;
        }
        if (r.isnar()) {
            fail(err, SQLSTATE_OUT_OF_RANGE, "posit16_1 result is NaR");
            return KWABI_ERR_BODY_RAISED;
        }
        *result = r.encoding();
        return KWABI_OK;
    } catch (...) {
        fail(err, SQLSTATE_NOT_SUPPORTED, "internal error in posit16_1 operator");
        return KWABI_ERR_BODY_RAISED;
    }
}

static const KwabiTypeBodies type_bodies = {
    .size = sizeof(KwabiTypeBodies),
    .version = KWABI_TYPE_BODIES_VERSION,
    .input = posit_input,
    .output = posit_output,
    .binop = posit_binop,
    .arg = nullptr,
};

const KwabiTypeBodies* kwabi_type_bodies(void) { return &type_bodies; }

// The extension entry point. The body needs no runtime services, so it keeps no table.
bool kwabi_ext_init(const KwabiV1* api) { return api != nullptr; }

}  // extern "C"
