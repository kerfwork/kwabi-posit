// body_test — the posit16_1 body through its exported table, with no PostgreSQL.
// Each check prints FAIL with its location; the program exits non-zero if any failed.

#include "kwabi.h"

#include <cstdint>
#include <cstdio>
#include <string>

extern "C" const KwabiTypeBodies* kwabi_type_bodies(void);

static int failures = 0;

#define CHECK(cond, ...)                                                    \
    do {                                                                    \
        if (!(cond)) {                                                      \
            ++failures;                                                     \
            std::fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__);       \
            std::fprintf(stderr, __VA_ARGS__);                              \
            std::fprintf(stderr, "\n");                                     \
        }                                                                   \
    } while (0)

static const KwabiTypeBodies* table() { return kwabi_type_bodies(); }

static KwabiStatus parse(const char* text, uint64_t* out, KwabiError* err) {
    return table()->input(text, out, err, nullptr);
}

static std::string format(uint64_t bits) {
    char buf[64] = {0};
    KwabiError err{};
    if (table()->output(bits, buf, sizeof buf, &err, nullptr) != KWABI_OK) return "<error>";
    return buf;
}

static KwabiStatus op(uint32_t code, uint64_t a, uint64_t b, uint64_t* r, KwabiError* err) {
    return table()->binop(code, a, b, r, err, nullptr);
}

// The encoding of a decimal, from the body's own input. Used as the operand source.
static uint64_t enc(const char* text) {
    uint64_t v = 0;
    KwabiError err{};
    if (parse(text, &v, &err) != KWABI_OK) {
        std::fprintf(stderr, "test setup: cannot parse %s\n", text);
        ++failures;
    }
    return v;
}

static void test_table() {
    CHECK(table()->size == sizeof(KwabiTypeBodies), "table size");
    CHECK(table()->version == KWABI_TYPE_BODIES_VERSION, "table version");
}

static void test_output() {
    CHECK(format(enc("1")) == "1", "1 prints as 1, got %s", format(enc("1")).c_str());
    CHECK(format(enc("-1")) == "-1", "-1 prints as -1, got %s", format(enc("-1")).c_str());
    CHECK(format(enc("0")) == "0", "0 prints as 0");
    CHECK(format(enc("0.5")) == "0.5", "0.5 prints as 0.5, got %s", format(enc("0.5")).c_str());
    CHECK(format(0x8000) == "NaR", "NaR prints as NaR, got %s", format(0x8000).c_str());
}

static void test_input_values() {
    uint64_t v = 0;
    KwabiError err{};
    CHECK(parse("1", &v, &err) == KWABI_OK && v == 0x4000, "1 has encoding 0x4000, got 0x%llx", (unsigned long long)v);
    CHECK(parse("0", &v, &err) == KWABI_OK && v == 0x0000, "0 has encoding 0");
}

static void test_syntax_refused() {
    const char* bad[] = {"", "-", "+1", " 1", "1 ", "0x10", "inf", "nan", "1.2.3",
                         "1e", "1e+", "e5", "1,5", "NaR"};
    for (const char* s : bad) {
        uint64_t v = 0;
        KwabiError err{};
        KwabiStatus st = parse(s, &v, &err);
        CHECK(st == KWABI_ERR_BODY_RAISED, "input \"%s\" should be refused", s);
        // 22P02 in PostgreSQL's SQLSTATE encoding: six bits per character, from '0'.
        const int invalid_text = ((('2' - '0') & 0x3F)) | ((('2' - '0') & 0x3F) << 6) |
                                 ((('P' - '0') & 0x3F) << 12) | ((('0' - '0') & 0x3F) << 18) |
                                 ((('2' - '0') & 0x3F) << 24);
        CHECK(err.sqlerrcode == invalid_text, "input \"%s\" should be 22P02, got %d", s, err.sqlerrcode);
    }
}

// Overflow saturates to maxpos / maxneg: that is posit behaviour, and not an error.
static void test_saturation() {
    uint64_t v = 0;
    KwabiError err{};
    CHECK(parse("1e30", &v, &err) == KWABI_OK && v == 0x7FFF,
          "1e30 saturates to maxpos (0x7fff), got 0x%llx", (unsigned long long)v);
    CHECK(parse("-1e30", &v, &err) == KWABI_OK && v == 0x8001,
          "-1e30 saturates to maxneg (0x8001), got 0x%llx", (unsigned long long)v);
}

// Every encoding except NaR must read back to itself through its printed text.
static void test_round_trip_all() {
    int bad = 0;
    for (uint64_t bits = 0; bits <= 0xFFFF; ++bits) {
        if (bits == 0x8000) continue;
        std::string s = format(bits);
        uint64_t back = 0;
        KwabiError err{};
        if (parse(s.c_str(), &back, &err) != KWABI_OK || back != bits) {
            if (bad < 5)
                std::fprintf(stderr, "round trip: 0x%04llx -> \"%s\" -> 0x%04llx\n",
                             (unsigned long long)bits, s.c_str(), (unsigned long long)back);
            ++bad;
        }
    }
    CHECK(bad == 0, "%d encodings did not round-trip through text", bad);
}

static void test_arithmetic() {
    KwabiError err{};
    uint64_t r = 0;
    CHECK(op(KWABI_TYPE_OP_ADD, enc("1"), enc("2"), &r, &err) == KWABI_OK && format(r) == "3",
          "1 + 2 = 3, got %s", format(r).c_str());
    CHECK(op(KWABI_TYPE_OP_SUB, enc("3"), enc("1"), &r, &err) == KWABI_OK && format(r) == "2",
          "3 - 1 = 2, got %s", format(r).c_str());
    CHECK(op(KWABI_TYPE_OP_MUL, enc("2"), enc("2"), &r, &err) == KWABI_OK && format(r) == "4",
          "2 * 2 = 4, got %s", format(r).c_str());
    CHECK(op(KWABI_TYPE_OP_DIV, enc("3"), enc("2"), &r, &err) == KWABI_OK && format(r) == "1.5",
          "3 / 2 = 1.5, got %s", format(r).c_str());
}

static void test_arithmetic_errors() {
    KwabiError err{};
    uint64_t r = 0;
    CHECK(op(KWABI_TYPE_OP_DIV, enc("7"), enc("0"), &r, &err) == KWABI_ERR_BODY_RAISED,
          "division by zero is refused");
    CHECK(op(KWABI_TYPE_OP_DIV, enc("7"), enc("1"), &r, &err) == KWABI_OK,
          "control: division by one is fine");
    CHECK(op(KWABI_TYPE_OP_MOD, enc("7"), enc("2"), &r, &err) == KWABI_ERR_BODY_RAISED,
          "modulo is refused for posits");
    CHECK(op(KWABI_TYPE_OP_ADD, 0x8000, enc("1"), &r, &err) == KWABI_ERR_BODY_RAISED,
          "a NaR operand gives NaR, which is refused");
}

static void test_comparisons() {
    KwabiError err{};
    uint64_t r = 0;
    CHECK(op(KWABI_TYPE_OP_LT, enc("1"), enc("2"), &r, &err) == KWABI_OK && r == 1, "1 < 2");
    CHECK(op(KWABI_TYPE_OP_LT, enc("2"), enc("1"), &r, &err) == KWABI_OK && r == 0, "control: 2 < 1 is false");
    CHECK(op(KWABI_TYPE_OP_LE, enc("2"), enc("2"), &r, &err) == KWABI_OK && r == 1, "2 <= 2");
    CHECK(op(KWABI_TYPE_OP_GT, enc("2"), enc("1"), &r, &err) == KWABI_OK && r == 1, "2 > 1");
    CHECK(op(KWABI_TYPE_OP_GE, enc("1"), enc("2"), &r, &err) == KWABI_OK && r == 0, "control: 1 >= 2 is false");
    CHECK(op(KWABI_TYPE_OP_EQ, enc("2"), enc("2"), &r, &err) == KWABI_OK && r == 1, "2 = 2");
    CHECK(op(KWABI_TYPE_OP_NE, enc("2"), enc("1"), &r, &err) == KWABI_OK && r == 1, "2 <> 1");
    // NaR: equal to itself, above every value, so the btree order is total.
    CHECK(op(KWABI_TYPE_OP_EQ, 0x8000, 0x8000, &r, &err) == KWABI_OK && r == 1, "NaR = NaR");
    CHECK(op(KWABI_TYPE_OP_GT, 0x8000, enc("1000"), &r, &err) == KWABI_OK && r == 1, "NaR > 1000");
}

static void test_order() {
    KwabiError err{};
    uint64_t r = 0;
    CHECK(op(KWABI_TYPE_OP_ORDER, enc("1"), enc("2"), &r, &err) == KWABI_OK && r == KWABI_TYPE_ORDER_LESS,
          "order 1 vs 2 is less");
    CHECK(op(KWABI_TYPE_OP_ORDER, enc("2"), enc("2"), &r, &err) == KWABI_OK && r == KWABI_TYPE_ORDER_EQUAL,
          "order 2 vs 2 is equal");
    CHECK(op(KWABI_TYPE_OP_ORDER, enc("2"), enc("1"), &r, &err) == KWABI_OK && r == KWABI_TYPE_ORDER_GREATER,
          "order 2 vs 1 is greater");
}

int main() {
    test_table();
    test_output();
    test_input_values();
    test_syntax_refused();
    test_saturation();
    test_round_trip_all();
    test_arithmetic();
    test_arithmetic_errors();
    test_comparisons();
    test_order();
    if (failures) {
        std::fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    std::printf("posit16_1 body: all checks passed\n");
    return 0;
}
