#include <errno.h>
#include "unity.h"
#include "build_info.h"

void setUp(void) {}
void tearDown(void) {}

static void test_formats_version(void)
{
	char buf[16];

	TEST_ASSERT_EQUAL_INT(5, build_info_format(buf, sizeof(buf), 1, 2, 3));
	TEST_ASSERT_EQUAL_STRING("1.2.3", buf);
}

static void test_rejects_small_buffer(void)
{
	char buf[4];

	TEST_ASSERT_EQUAL_INT(-ENOSPC, build_info_format(buf, sizeof(buf), 10, 20, 30));
}

int main(void)
{
	UNITY_BEGIN();
	RUN_TEST(test_formats_version);
	RUN_TEST(test_rejects_small_buffer);
	return UNITY_END();
}
