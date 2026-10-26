#include "build_info.h"

int main(void)
{
	char ver[16];

	/* Bring-up order (references/baremetal.md): vendor SystemInit() already ran from the
	 * reset handler; next add clock config, a UART/RTT log and print the boot line. */
	if (build_info_format(ver, sizeof(ver), 0, 1, 0) < 0) {
		for (;;) {
		}
	}
	/* log_printf("boot ok v%s\n", ver);  <- first slice: make this line appear in artifacts/ */
	for (;;) {
		__asm volatile("wfi");
	}
}
