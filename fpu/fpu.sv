/*
 * Floating point processing unit.
 *
 * This module can perfomance next tasks with two operands:
 *      - Add
 *      - Subtract
 *      - Multiply
 *      - Division
 *
 * Author: Aleksandr Novozhilov
 * Creating date: 2018-02-12
 *
 */
`include "macro.sv"


/* Operation type.
 */
typedef enum logic[3:0] {
                add_op = 4'b0000  // Sum A and B
        ,       sub_op = 4'b0001  // Subtract A from B
        ,       mul_op = 4'b0010  // Multiply A to B
        ,       div_op = 4'b0011  // Division A by B
                               // Other values are reserved
        } Operation_t;


module fpu
        #(parameter bitness=32)
(
        input clock,
        input reset,

        input  input_rdy,
        output input_ack,

        output output_rdy,
        input  output_ack,

        input [bitness - 1:0] data_a,
        input [bitness - 1:0] data_b,

        input Operation_t operation,

        output [bitness - 1:0] result
);
        enum logic[3:0] {
                        unpack     = 4'b0000
                ,       pack       = 4'b0001
                ,       align      = 4'b0010
                ,       normalize  = 4'b0011
                ,       add_0      = 4'b0100
                ,       add_1      = 4'b0101
                ,       sub        = 4'b0110
                ,       mul        = 4'b0111
                ,       div        = 4'b1000
                ,       put_result = 4'b1001
                ,       get_input  = 4'b1010
                ,       special    = 4'b1011
        } state;

        logic [bitness - 1:0]   s_result
                            , s_out_result;
        logic  s_output_rdy
            ,s_input_ack;

        logic [bitness - 1:0]   s_data_a
                            , s_data_b;

        logic   data_a_sign
            , data_b_sign
            , result_sign;

        logic[`EXP_SIZE(bitness) - 1:0]   data_a_exp
                                      , data_b_exp
                                      , result_exp
                                      , exp_difference;

        // Inner mantissa with hidden bit.
        logic[`MANT_SIZE(bitness):0]   data_a_mantissa
                                   , data_b_mantissa
                                   , result_mantissa;


        always @(posedge clock) begin
                if (reset) begin
                        state        <= get_input;
                        s_output_rdy <= 0;
                        s_input_ack  <= 0;
                end

                case (state)
                        get_input: begin
                                if (input_rdy) begin
                                        s_data_a <= data_a;
                                        s_data_b <= data_b;

                                        s_input_ack <= 1;

                                        state <= unpack;
                                end
                        end

                        /* Input numbers unpacking
                         */
                        unpack: begin
                                data_a_mantissa <= {1'b1, s_data_a[`MANT_SIZE(bitness) - 1:0]};
                                data_a_exp      <= s_data_a[bitness - 2: `MANT_SIZE(bitness)] - `BIAS_COEFF(bitness);
                                data_a_sign     <= s_data_a[bitness - 1];

                                data_b_mantissa <= {1'b1, s_data_b[`MANT_SIZE(bitness) - 1:0]};
                                data_b_exp      <= s_data_b[bitness - 2: `MANT_SIZE(bitness)] - `BIAS_COEFF(bitness);
                                data_b_sign     <= s_data_b[bitness - 1];

                                state <= special;

                        end

                        /* Special cases
                         */
                        special: begin
                                // Inf A case
                                if (data_a_exp == `MAX_EXP_VALUE(bitness) && data_a_mantissa[`MANT_SIZE(bitness) - 1:0] == 0) begin
                                        s_result[bitness - 1]                      <= 1;
                                        s_result[bitness - 2: `MANT_SIZE(bitness)] <= '1;
                                        s_result[`MANT_SIZE(bitness) - 1:0]        <= 0;
                                        state <= put_result;
                                end
                                else
                                // Inf B case
                                if (data_b_exp == `MAX_EXP_VALUE(bitness) && data_b_mantissa[`MANT_SIZE(bitness) - 1:0] == 0) begin
                                        s_result[bitness - 1]                      <= 1;
                                        s_result[bitness - 2: `MANT_SIZE(bitness)] <= '1;
                                        s_result[`MANT_SIZE(bitness) - 1:0]        <= 0;
                                        state <= put_result;
                                end
                                else
                                // Case if A or B is NaN
                                if ((data_a_exp == `MAX_EXP_VALUE(bitness) && data_a_mantissa[`MANT_SIZE(bitness) - 1:0] != 0) ||
                                    (data_b_exp == `MAX_EXP_VALUE(bitness) && data_b_mantissa[`MANT_SIZE(bitness) - 1:0] != 0)) begin
                                        s_result[bitness - 1]                      <= 1;
                                        s_result[bitness - 2: `MANT_SIZE(bitness)] <= '1;
                                        s_result[`MANT_SIZE(bitness) - 1:0]        <= '1;
                                        state <= put_result;
                                end
                                else begin
                                        /* Hadling operations.
                                         *
                                         */
                                        case (operation)
                                                add_op: begin
                                                        state <= align;
                                                end
                                                mul_op: begin
                                                        state <= mul;
                                                end
                                                div_op: begin
                                                        state <= div;
                                                end
                                                default: begin
                                                        state <= put_result;
                                                end
                                        endcase
                                end
                        end

                        /* Input numbers aligning
                         */
                        align: begin
                                if ($signed(data_a_exp) > $signed(data_b_exp)) begin
                                        exp_difference  = $signed(data_a_exp) - $signed(data_b_exp);
                                        data_b_exp      = data_a_exp;
                                        data_b_mantissa = data_b_mantissa >> exp_difference;
                                end
                                else if ($signed(data_a_exp) < $signed(data_b_exp)) begin
                                        exp_difference = $signed(data_b_exp) - $signed(data_a_exp);
                                        data_a_exp      = data_b_exp;
                                        data_a_mantissa = data_a_mantissa >> exp_difference;
                                end
                                state <= add_0;
                        end

                        add_0: begin
                                result_exp <= data_a_exp;
                                if (data_a_sign == data_b_sign) begin
                                        result_sign     <= data_a_sign;
                                        result_mantissa <= data_a_mantissa[`MANT_SIZE(bitness) - 1:0] + data_b_mantissa[`MANT_SIZE(bitness) - 1:0];
                                end
                                else
                                if (data_a_mantissa >= data_b_mantissa) begin
                                        result_sign     <= data_a_sign;
                                        result_mantissa <= data_a_mantissa[`MANT_SIZE(bitness) - 1:0] - data_b_mantissa[`MANT_SIZE(bitness) - 1:0];
                                end
                                else if (data_a_mantissa < data_b_mantissa) begin
                                        result_sign     <= data_b_sign;
                                        result_mantissa <= data_b_mantissa[`MANT_SIZE(bitness) - 1:0] - data_a_mantissa[`MANT_SIZE(bitness) - 1:0];
                                end
                                state <= add_1;
                        end

                        add_1: begin
                                // Align result to the right if overflow occures.
                                if (result_mantissa[`MANT_SIZE(bitness)]) begin
                                        result_exp      <= result_exp + 1;
                                        result_mantissa <= result_mantissa >> 1;
                                end
                                state <= normalize;
                        end

                        mul: begin
                                result_sign     <= data_a_sign || data_b_sign;
                                result_exp      <= data_a_exp + data_b_exp;
                                result_mantissa <= data_a_mantissa * data_b_mantissa;

                                state <= normalize;
                        end

                        div: begin
                                result_sign     <= data_a_sign || data_b_sign;
                                result_exp      <= data_a_exp - data_b_exp;
                                result_mantissa <= data_a_mantissa / data_b_mantissa;

                                state <= normalize;
                        end

                        normalize: begin
                                //$display("%b %b", data_a_exp, data_a_mantissa);
                                //$display("%b %b", data_b_exp, data_b_mantissa);
                                //$display("Normolize %b %b %d", result_exp, result_mantissa, (`MANT_SIZE(bitness) + 1));

                                //if (result_mantissa[`MANT_SIZE(bitness)] == 0 && $signed(result_exp) > -126) begin
                                //        result_exp <= result_exp - 1;
                                //        result_mantissa <= result_mantissa << 1;
                                //end

                                // If hidden bit is not zero after adding
                                //if (result_mantissa[`MANT_SIZE(bitness)] == 0) begin
                                //
                                //end
                                state <= pack;
                        end

                        // Packing result, work is done.
                        pack: begin
                                s_result[bitness - 1]                      <= result_sign;
                                s_result[bitness - 2: `MANT_SIZE(bitness)] <= result_exp + `BIAS_COEFF(bitness);
                                s_result[`MANT_SIZE(bitness) - 1:0]        <= result_mantissa[`MANT_SIZE(bitness) - 1:0];

                                state <= put_result;
                        end

                        put_result: begin
                                s_out_result <= s_result;
                                s_output_rdy <= 1;

                                if (s_output_rdy && output_ack) begin
                                        s_output_rdy <= 0;
                                        state        <= get_input;
                                end
                        end

                endcase
        end

        assign result     = s_result;
        assign output_rdy = s_output_rdy;
        assign input_ack  = s_input_ack;

endmodule
