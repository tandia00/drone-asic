#include "../sahel1.h"

void pwm_setup(int ch, uint32_t period, uint32_t duty)
{
    PWM_PERIOD(ch) = period;
    PWM_DUTY(ch)   = duty;
    PWM_CFG(ch)    = 1;       /* enable */
}

void pwm_set_duty(int ch, uint32_t duty) { PWM_DUTY(ch) = duty; }
void pwm_disable(int ch)                 { PWM_CFG(ch) = 0; }
