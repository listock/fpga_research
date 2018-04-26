 /*
 * Common FPU module macros.
 *
 * Author: Aleksandr Novozhilov
 * Creating date: 2018-03-14
 *
 */

 /* Exponent size macro.
  */
`define EXP_SIZE(bitness) (bitness == 256? 19: bitness == 128? 15: bitness == 64? 11: bitness == 32? 8: 5)

/* Mantissa size macro.
 */
`define MANT_SIZE(bitness) (bitness == 256? 236: bitness == 128? 112: bitness == 64? 52: bitness == 32? 23: 10)

/* Macro with exponent's bias coefficient.
 */
`define BIAS_COEFF(bitness) ((2 ** (`EXP_SIZE(bitness) - 1)) - 1)

/* Max exponent value.
 */
`define MAX_EXP_VALUE(bitness) (2 ** (`EXP_SIZE(bitness) - 1))
