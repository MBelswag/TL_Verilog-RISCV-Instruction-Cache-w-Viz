\m5_TLV_version 1d: tl-x.org
\SV
   // This code can be found in: https://github.com/stevehoover/RISC-V_MYTH_Workshop
   
   m4_include_lib(['https://raw.githubusercontent.com/BalaDhinesh/RISC-V_MYTH_Workshop/master/tlv_lib/risc-v_shell_lib.tlv'])

\SV
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)
\TLV

   // /====================\
   // | Sum 1 to 9 Program |
   // \====================/
   //
   // Program for MYTH Workshop to test RV32I
   // Add 1,2,3,...,9 (in that order).
   //
   // Regs:
   //  r10 (a0): In: 0, Out: final sum
   //  r12 (a2): 10
   //  r13 (a3): 1..10
   //  r14 (a4): Sum
   // 
   // External to function:
   m4_asm(ADD, r10, r0, r0)             // Initialize r10 (a0) to 0.
   // Function:
   m4_asm(ADD, r14, r10, r0)            // Initialize sum register a4 with 0x0
   m4_asm(ADDI, r12, r10, 1010)         // Store count of 10 in register a2.
   m4_asm(ADD, r13, r10, r0)            // Initialize intermediate sum register a3 with 0
   // Loop:
   m4_asm(ADD, r14, r13, r14)           // Incremental addition
   m4_asm(ADDI, r13, r13, 1)            // Increment intermediate register by 1
   m4_asm(BLT, r13, r12, 1111111111000) // If a3 is less than a2, branch to label named <loop>
   m4_asm(ADD, r10, r14, r0)            // Store final result to register a0 so that it can be read by main program
   m4_asm(SW, r0, r10, 100)             // Store final result to address 4.
   m4_asm(LW, r15, r0, 100)             // Load final result from address 4 into x15.
   
   // Optional:
   // m4_asm(JAL, r7, 00000000000000000000) // Done. Jump to itself (infinite loop). (Up to 20-bit signed immediate plus implicit 0 bit (unlike JALR) provides byte address; last immediate bit should also be 0)
   m4_define_hier(['M4_IMEM'], M4_NUM_INSTRS)
   
   |cpu
      @0
         $reset = *reset;
         $pc[31:0] = >>1$reset ? 32'b0 :
               >>3$valid_taken_br ? >>3$br_tgt_pc :
               >>3$valid_jump ? (>>3$is_jal ? >>3$br_tgt_pc : >>3$jalr_tgt_pc) :
               >>3$valid_load ? >>3$inc_pc :
                                    >>1$inc_pc;
         $inc_pc[31:0] = $pc + 32'd4;
         $imem_rd_en = !$reset;
         $imem_rd_addr[M4_IMEM_INDEX_CNT-1:0] = $pc[M4_IMEM_INDEX_CNT+1:2];
      @1
         // ---------------------------------------------------------------
         // 2-way set-associative instruction cache
         //
         // m4+imem(@1) backing instruction memory. There are no cache
         // stalls yet, so on a cache miss, decode uses $imem_rd_data immediately
         // and the cache fills with that same instruction.
         //
         // RISC-V instructions are word-aligned, PC[1:0] ignored.
         //   set index = PC[3:2]   // 4 sets
         //   tag       = PC[31:4]
         // ---------------------------------------------------------------
         $icache_set_index[1:0] = $pc[3:2];
         $icache_tag[27:0] = $pc[31:4];

         // Selected set state from previous fetch. The >>1 references
         // are cache storage state, not for pipeline alignment purpose
         
         $way0_valid = ($icache_set_index == 2'd0) ? >>1$icache_s0_w0_valid :
                       ($icache_set_index == 2'd1) ? >>1$icache_s1_w0_valid :
                       ($icache_set_index == 2'd2) ? >>1$icache_s2_w0_valid :
                                                     >>1$icache_s3_w0_valid;
         $way1_valid = ($icache_set_index == 2'd0) ? >>1$icache_s0_w1_valid :
                       ($icache_set_index == 2'd1) ? >>1$icache_s1_w1_valid :
                       ($icache_set_index == 2'd2) ? >>1$icache_s2_w1_valid :
                                                     >>1$icache_s3_w1_valid;
         $way0_tag[27:0] = ($icache_set_index == 2'd0) ? >>1$icache_s0_w0_tag :
                           ($icache_set_index == 2'd1) ? >>1$icache_s1_w0_tag :
                           ($icache_set_index == 2'd2) ? >>1$icache_s2_w0_tag :
                                                         >>1$icache_s3_w0_tag;
         $way1_tag[27:0] = ($icache_set_index == 2'd0) ? >>1$icache_s0_w1_tag :
                           ($icache_set_index == 2'd1) ? >>1$icache_s1_w1_tag :
                           ($icache_set_index == 2'd2) ? >>1$icache_s2_w1_tag :
                                                         >>1$icache_s3_w1_tag;
         $icache_way0_instr[31:0] = ($icache_set_index == 2'd0) ? >>1$icache_s0_w0_instr :
                                    ($icache_set_index == 2'd1) ? >>1$icache_s1_w0_instr :
                                    ($icache_set_index == 2'd2) ? >>1$icache_s2_w0_instr :
                                                                  >>1$icache_s3_w0_instr;
         $icache_way1_instr[31:0] = ($icache_set_index == 2'd0) ? >>1$icache_s0_w1_instr :
                                    ($icache_set_index == 2'd1) ? >>1$icache_s1_w1_instr :
                                    ($icache_set_index == 2'd2) ? >>1$icache_s2_w1_instr :
                                                                  >>1$icache_s3_w1_instr;
         $icache_rr_bit = ($icache_set_index == 2'd0) ? >>1$icache_s0_replace_toggle :
                          ($icache_set_index == 2'd1) ? >>1$icache_s1_replace_toggle :
                          ($icache_set_index == 2'd2) ? >>1$icache_s2_replace_toggle :
                                                        >>1$icache_s3_replace_toggle;
                                                        
         // Way comparisons and hit/miss result for current fetch
         $way0_hit = $way0_valid && ($way0_tag == $icache_tag);
         $way1_hit = $way1_valid && ($way1_tag == $icache_tag);
         $icache_hit = $way0_hit || $way1_hit;
         $icache_miss = !$icache_hit;
         $icache_hit_instr[31:0] = $way0_hit ? $icache_way0_instr :
                                               $icache_way1_instr;

         // Replacement:
         //   1. Fill invalid way 0 first.
         //   2. Else fill invalid way 1.
         //   3. Else use the per-set roundrobin/toggle bit.
         $chosen_replace_way = !$way0_valid ? 1'b0 :
                               !$way1_valid ? 1'b1 :
                                              $icache_rr_bit;
         $icache_fill = !$reset && $icache_miss;

         $icache_fill_s0_w0 = $icache_fill && ($icache_set_index == 2'd0) && ($chosen_replace_way == 1'b0);
         $icache_fill_s0_w1 = $icache_fill && ($icache_set_index == 2'd0) && ($chosen_replace_way == 1'b1);
         $icache_fill_s1_w0 = $icache_fill && ($icache_set_index == 2'd1) && ($chosen_replace_way == 1'b0);
         $icache_fill_s1_w1 = $icache_fill && ($icache_set_index == 2'd1) && ($chosen_replace_way == 1'b1);
         $icache_fill_s2_w0 = $icache_fill && ($icache_set_index == 2'd2) && ($chosen_replace_way == 1'b0);
         $icache_fill_s2_w1 = $icache_fill && ($icache_set_index == 2'd2) && ($chosen_replace_way == 1'b1);
         $icache_fill_s3_w0 = $icache_fill && ($icache_set_index == 2'd3) && ($chosen_replace_way == 1'b0);
         $icache_fill_s3_w1 = $icache_fill && ($icache_set_index == 2'd3) && ($chosen_replace_way == 1'b1);

         // Cache storage. Each set has way 0 and way 1 valid/tag/instr.
         // On miss, fill with the same $imem_rd_data used by decode.
         $icache_s0_w0_valid = $reset ? 1'b0 : ($icache_fill_s0_w0 ? 1'b1 : >>1$icache_s0_w0_valid);
         $icache_s0_w1_valid = $reset ? 1'b0 : ($icache_fill_s0_w1 ? 1'b1 : >>1$icache_s0_w1_valid);
         $icache_s1_w0_valid = $reset ? 1'b0 : ($icache_fill_s1_w0 ? 1'b1 : >>1$icache_s1_w0_valid);
         $icache_s1_w1_valid = $reset ? 1'b0 : ($icache_fill_s1_w1 ? 1'b1 : >>1$icache_s1_w1_valid);
         $icache_s2_w0_valid = $reset ? 1'b0 : ($icache_fill_s2_w0 ? 1'b1 : >>1$icache_s2_w0_valid);
         $icache_s2_w1_valid = $reset ? 1'b0 : ($icache_fill_s2_w1 ? 1'b1 : >>1$icache_s2_w1_valid);
         $icache_s3_w0_valid = $reset ? 1'b0 : ($icache_fill_s3_w0 ? 1'b1 : >>1$icache_s3_w0_valid);
         $icache_s3_w1_valid = $reset ? 1'b0 : ($icache_fill_s3_w1 ? 1'b1 : >>1$icache_s3_w1_valid);

         $icache_s0_w0_tag[27:0] = $reset ? 28'b0 : ($icache_fill_s0_w0 ? $icache_tag : >>1$icache_s0_w0_tag);
         $icache_s0_w1_tag[27:0] = $reset ? 28'b0 : ($icache_fill_s0_w1 ? $icache_tag : >>1$icache_s0_w1_tag);
         $icache_s1_w0_tag[27:0] = $reset ? 28'b0 : ($icache_fill_s1_w0 ? $icache_tag : >>1$icache_s1_w0_tag);
         $icache_s1_w1_tag[27:0] = $reset ? 28'b0 : ($icache_fill_s1_w1 ? $icache_tag : >>1$icache_s1_w1_tag);
         $icache_s2_w0_tag[27:0] = $reset ? 28'b0 : ($icache_fill_s2_w0 ? $icache_tag : >>1$icache_s2_w0_tag);
         $icache_s2_w1_tag[27:0] = $reset ? 28'b0 : ($icache_fill_s2_w1 ? $icache_tag : >>1$icache_s2_w1_tag);
         $icache_s3_w0_tag[27:0] = $reset ? 28'b0 : ($icache_fill_s3_w0 ? $icache_tag : >>1$icache_s3_w0_tag);
         $icache_s3_w1_tag[27:0] = $reset ? 28'b0 : ($icache_fill_s3_w1 ? $icache_tag : >>1$icache_s3_w1_tag);

         $icache_s0_w0_instr[31:0] = $reset ? 32'b0 : ($icache_fill_s0_w0 ? $imem_rd_data : >>1$icache_s0_w0_instr);
         $icache_s0_w1_instr[31:0] = $reset ? 32'b0 : ($icache_fill_s0_w1 ? $imem_rd_data : >>1$icache_s0_w1_instr);
         $icache_s1_w0_instr[31:0] = $reset ? 32'b0 : ($icache_fill_s1_w0 ? $imem_rd_data : >>1$icache_s1_w0_instr);
         $icache_s1_w1_instr[31:0] = $reset ? 32'b0 : ($icache_fill_s1_w1 ? $imem_rd_data : >>1$icache_s1_w1_instr);
         $icache_s2_w0_instr[31:0] = $reset ? 32'b0 : ($icache_fill_s2_w0 ? $imem_rd_data : >>1$icache_s2_w0_instr);
         $icache_s2_w1_instr[31:0] = $reset ? 32'b0 : ($icache_fill_s2_w1 ? $imem_rd_data : >>1$icache_s2_w1_instr);
         $icache_s3_w0_instr[31:0] = $reset ? 32'b0 : ($icache_fill_s3_w0 ? $imem_rd_data : >>1$icache_s3_w0_instr);
         $icache_s3_w1_instr[31:0] = $reset ? 32'b0 : ($icache_fill_s3_w1 ? $imem_rd_data : >>1$icache_s3_w1_instr);

         // Put the replacement bit for the set that was filled.
         $icache_s0_replace_toggle = $reset ? 1'b0 : (($icache_fill_s0_w0 || $icache_fill_s0_w1) ? ~$chosen_replace_way : >>1$icache_s0_replace_toggle);
         $icache_s1_replace_toggle = $reset ? 1'b0 : (($icache_fill_s1_w0 || $icache_fill_s1_w1) ? ~$chosen_replace_way : >>1$icache_s1_replace_toggle);
         $icache_s2_replace_toggle = $reset ? 1'b0 : (($icache_fill_s2_w0 || $icache_fill_s2_w1) ? ~$chosen_replace_way : >>1$icache_s2_replace_toggle);
         $icache_s3_replace_toggle = $reset ? 1'b0 : (($icache_fill_s3_w0 || $icache_fill_s3_w1) ? ~$chosen_replace_way : >>1$icache_s3_replace_toggle);

         // Viz counters.
         $icache_access_count[31:0] = $reset ? 32'd0 : (>>1$icache_access_count + 32'd1);
         $icache_hit_count[31:0] = $reset ? 32'd0 : (>>1$icache_hit_count + ($icache_hit ? 32'd1 : 32'd0));
         $icache_miss_count[31:0] = $reset ? 32'd0 : (>>1$icache_miss_count + ($icache_miss ? 32'd1 : 32'd0));

         // ---------------------------------------------------------------
         // Cache signals
         //   icache_viz_event = 0 reset/idle, 1 hit way 0, 2 hit way 1,
         //                      3 miss fill way 0, 4 miss fill way 1
         // ---------------------------------------------------------------
       
         $icache_viz_selected_set[1:0] = $icache_set_index;
         
         $icache_viz_selected_way[1:0] = $way0_hit ? 2'd0 :
                                         $way1_hit ? 2'd1 :
                                                     {1'b0, $chosen_replace_way};
         $icache_viz_event[2:0] = $reset ? 3'd0 :
                                  $way0_hit ? 3'd1 :
                                  $way1_hit ? 3'd2 :
                                  ($icache_fill && ($chosen_replace_way == 1'b0)) ? 3'd3 :
                                  ($icache_fill && ($chosen_replace_way == 1'b1)) ? 3'd4 :
                                                                                     3'd0;

         // Whole-cache after the current fill decision. Bit order is
         // {s3w1,s3w0,s2w1,s2w0, s1w1,s1w0,s0w1,s0w0}; this gives an easy display.
         $icache_viz_all_valids[7:0] = {$icache_s3_w1_valid, $icache_s3_w0_valid,
                                        $icache_s2_w1_valid, $icache_s2_w0_valid,
                                        $icache_s1_w1_valid, $icache_s1_w0_valid,
                                        $icache_s0_w1_valid, $icache_s0_w0_valid};
         $instr[31:0] = $icache_hit ? $icache_hit_instr : $imem_rd_data;
         $opcode[6:0] = $instr[6:0];
         $is_i_instr = $instr[6:2] ==? 5'b0000x ||
                 $instr[6:2] ==? 5'b001x0 ||
                 $instr[6:2] ==? 5'b11001;
         $is_s_instr = $instr[6:2] ==? 5'b0100x;
         $is_b_instr = $instr[6:2] ==? 5'b11000;
         $is_u_instr = $instr[6:2] ==? 5'b0x101;
         $is_j_instr = $instr[6:2] ==? 5'b11011;
         $is_r_instr = $instr[6:2] ==? 5'b01011 ||
                 $instr[6:2] ==? 5'b01100 ||
                 $instr[6:2] ==? 5'b01110 ||
                 $instr[6:2] ==? 5'b10100;

         $rs2_valid = $is_r_instr || $is_s_instr || $is_b_instr;
         ?$rs2_valid
            $rs2[4:0] = $instr[24:20];
         $rs1_valid = $is_r_instr || $is_i_instr || $is_s_instr || $is_b_instr;
         ?$rs1_valid
            $rs1[4:0] = $instr[19:15];
         $rd_valid = $is_r_instr || $is_i_instr || $is_u_instr || $is_j_instr;
         ?$rd_valid
            $rd[4:0] = $instr[11:7];
         $funct3_valid = $is_r_instr || $is_i_instr || $is_s_instr || $is_b_instr;
         ?$funct3_valid
            $funct3[2:0] = $instr[14:12];
         $funct7_valid = $is_r_instr || $is_i_instr;
         ?$funct7_valid
            $funct7[6:0] = $instr[31:25];
         $imm[31:0] = $is_i_instr ? {{21{$instr[31]}}, $instr[30:20]} :
                $is_s_instr ? {{21{$instr[31]}}, $instr[30:25], $instr[11:8], $instr[7]} :
                $is_b_instr ? {{20{$instr[31]}}, $instr[7], $instr[30:25], $instr[11:8], 1'b0} :
                $is_u_instr ? {$instr[31], $instr[30:20], $instr[19:12], 12'b0} :
                $is_j_instr ? {{12{$instr[31]}}, $instr[19:12], $instr[20], $instr[30:25], $instr[24:21], 1'b0} : 32'b0;
         $dec_bits[10:0] = {$funct7[5], $funct3, $opcode};
         $is_lui   = $dec_bits ==? 11'bx_xxx_0110111;
         $is_auipc = $dec_bits ==? 11'bx_xxx_0010111;
         $is_jal   = $dec_bits ==? 11'bx_xxx_1101111;
         $is_jalr  = $dec_bits ==? 11'bx_000_1100111;
         $is_beq  = $dec_bits ==? 11'bx_000_1100011;
         $is_bne  = $dec_bits ==? 11'bx_001_1100011;
         $is_blt  = $dec_bits ==? 11'bx_100_1100011;
         $is_bge  = $dec_bits ==? 11'bx_101_1100011;
         $is_bltu = $dec_bits ==? 11'bx_110_1100011;
         $is_bgeu = $dec_bits ==? 11'bx_111_1100011;
         $is_load = $opcode == 7'b0000011;
         $is_sb   = $dec_bits ==? 11'bx_000_0100011;
         $is_sh   = $dec_bits ==? 11'bx_001_0100011;
         $is_sw   = $dec_bits ==? 11'bx_010_0100011;
         $is_addi  = $dec_bits ==? 11'bx_000_0010011;
         $is_slti  = $dec_bits ==? 11'bx_010_0010011;
         $is_sltiu = $dec_bits ==? 11'bx_011_0010011;
         $is_xori  = $dec_bits ==? 11'bx_100_0010011;
         $is_ori   = $dec_bits ==? 11'bx_110_0010011;
         $is_andi  = $dec_bits ==? 11'bx_111_0010011;
         $is_slli  = $dec_bits ==? 11'b0_001_0010011;
         $is_srli  = $dec_bits ==? 11'b0_101_0010011;
         $is_srai  = $dec_bits ==? 11'b1_101_0010011;
         $is_add  = $dec_bits ==? 11'b0_000_0110011;
         $is_sub  = $dec_bits ==? 11'b1_000_0110011;
         $is_sll  = $dec_bits ==? 11'b0_001_0110011;
         $is_slt  = $dec_bits ==? 11'b0_010_0110011;
         $is_sltu = $dec_bits ==? 11'b0_011_0110011;
         $is_xor  = $dec_bits ==? 11'b0_100_0110011;
         $is_srl  = $dec_bits ==? 11'b0_101_0110011;
         $is_sra  = $dec_bits ==? 11'b1_101_0110011;
         $is_or   = $dec_bits ==? 11'b0_110_0110011;
         $is_and  = $dec_bits ==? 11'b0_111_0110011;
         `BOGUS_USE($is_lui $is_auipc $is_jal $is_jalr
                    $is_beq $is_bne $is_blt $is_bge $is_bltu $is_bgeu
                    $is_load $is_sb $is_sh $is_sw
                    $is_addi $is_slti $is_sltiu $is_xori $is_ori $is_andi
                    $is_slli $is_srli $is_srai
                    $is_add $is_sub $is_sll $is_slt $is_sltu
                    $is_xor $is_srl $is_sra $is_or $is_and)
      @2
         $rf_rd_en1 = $rs1_valid;
         $rf_rd_index1[4:0] = $rs1;

         $rf_rd_en2 = $rs2_valid;
         $rf_rd_index2[4:0] = $rs2;

         $br_tgt_pc[31:0] = $pc + $imm;

      @3
         $valid = !$reset &&
                  !(>>1$valid_taken_br || >>2$valid_taken_br ||
                    >>1$valid_jump || >>2$valid_jump ||
                    >>1$valid_load || >>2$valid_load);

         $src1_value[31:0] =
            (>>1$rf_wr_en && (>>1$rf_wr_index == $rs1)) ? >>1$rf_wr_data :
            (>>2$rf_wr_en && (>>2$rf_wr_index == $rs1)) ? >>2$rf_wr_data :
                                                            $rf_rd_data1;
         $src2_value[31:0] =
            (>>1$rf_wr_en && (>>1$rf_wr_index == $rs2)) ? >>1$rf_wr_data :
            (>>2$rf_wr_en && (>>2$rf_wr_index == $rs2)) ? >>2$rf_wr_data :
                                                            $rf_rd_data2;

         $sltu_rslt = $src1_value < $src2_value;
         $sltiu_rslt = $src1_value < $imm;
         $sra_rslt[63:0] =
            {{32{$src1_value[31]}}, $src1_value} >> $src2_value[4:0];
         $srai_rslt[63:0] =
            {{32{$src1_value[31]}}, $src1_value} >> $imm[4:0];

         $result[31:0] =
            $is_andi  ? $src1_value & $imm :
            $is_ori   ? $src1_value | $imm :
            $is_xori  ? $src1_value ^ $imm :
            ($is_load || $is_s_instr) ? $src1_value + $imm :
            $is_addi  ? $src1_value + $imm :
            $is_slli  ? $src1_value << $imm[4:0] :
            $is_srli  ? $src1_value >> $imm[4:0] :
            $is_srai  ? $srai_rslt[31:0] :
            $is_sltiu ? {31'b0, $sltiu_rslt} :
            $is_slti  ? ($src1_value[31] == $imm[31] ?
                         {31'b0, $sltiu_rslt} :
                         {31'b0, $src1_value[31]}) :
            $is_and   ? $src1_value & $src2_value :
            $is_or    ? $src1_value | $src2_value :
            $is_xor   ? $src1_value ^ $src2_value :
            $is_add   ? $src1_value + $src2_value :
            $is_sub   ? $src1_value - $src2_value :
            $is_sll   ? $src1_value << $src2_value[4:0] :
            $is_srl   ? $src1_value >> $src2_value[4:0] :
            $is_sra   ? $sra_rslt[31:0] :
            $is_sltu  ? {31'b0, $sltu_rslt} :
            $is_slt   ? ($src1_value[31] == $src2_value[31] ?
                         {31'b0, $sltu_rslt} :
                         {31'b0, $src1_value[31]}) :
            $is_lui   ? $imm :
            $is_auipc ? $pc + $imm :
            ($is_jal || $is_jalr) ? $pc + 32'd4 :
                                    32'b0;

         $result_valid = $is_andi || $is_ori || $is_xori || $is_addi ||
                         $is_slli || $is_srli || $is_srai ||
                         $is_slti || $is_sltiu ||
                         $is_and || $is_or || $is_xor || $is_add || $is_sub ||
                         $is_sll || $is_srl || $is_sra || $is_slt || $is_sltu ||
                         $is_lui || $is_auipc || $is_jal || $is_jalr;

         $taken_br = $is_beq  ? ($src1_value == $src2_value) :
                     $is_bne  ? ($src1_value != $src2_value) :
                     $is_blt  ? (($src1_value < $src2_value) ^ ($src1_value[31] != $src2_value[31])) :
                     $is_bge  ? (($src1_value >= $src2_value) ^ ($src1_value[31] != $src2_value[31])) :
                     $is_bltu ? ($src1_value < $src2_value) :
                     $is_bgeu ? ($src1_value >= $src2_value) :
                                 1'b0;

         $valid_taken_br = $valid && $taken_br;
         $valid_jump = $valid && ($is_jal || $is_jalr);
         $jalr_tgt_pc[31:0] = $src1_value + $imm;
         $valid_load = $valid && $is_load;
      @4
         $dmem_rd_en = $valid_load;
         $dmem_wr_en = $valid && $is_s_instr;
         $dmem_addr[3:0] = $result[5:2];
         $dmem_wr_data[31:0] = $src2_value;
         $ld_data[31:0] = $dmem_rd_data;

         $rf_wr_en = ($valid && $rd_valid && ($rd != 5'b0) && $result_valid) ||
                     (>>2$valid_load && (>>2$rd != 5'b0));
         $rf_wr_index[4:0] = >>2$valid_load ? >>2$rd : $rd;
         $rf_wr_data[31:0] = >>2$valid_load ? >>2$ld_data : $result;
   *passed = |cpu/xreg[15]>>5$value == (1+2+3+4+5+6+7+8+9);
   *failed = 1'b0;

   |cpu
      m4+imem(@1)
      m4+rf(@2, @4)
      m4+dmem(@4)

      @1
         \viz_js
            box: {left: -4, top: -4, width: 260, height: 198,
                  strokeWidth: 1, stroke: "#cbd5e1", fill: "#ffffff"},
            template: {
               title: ["Text", "2-Way Instruction-Cache",
                       {left: 10, top: 8,
                        fontSize: 12,
                        fill: "#111827"}],
               subtitle: ["Text", "4 sets x 2 ways",
                          {left: 10, top: 26,
                           fontSize: 9,
                           fill: "#475569"}],

               s0: ["Text", "S0", {left: 10, top: 54,
                                    fontSize: 9, fill: "#475569"}],
               s1: ["Text", "S1", {left: 10, top: 84,
                                    fontSize: 9, fill: "#475569"}],
               s2: ["Text", "S2", {left: 10, top: 114,
                                    fontSize: 9, fill: "#475569"}],
               s3: ["Text", "S3", {left: 10, top: 144,
                                    fontSize: 9, fill: "#475569"}],
               w0: ["Text", "W0", {left: 45, top: 38,
                                    fontSize: 9, fill: "#475569"}],
               w1: ["Text", "W1", {left: 83, top: 38,
                                    fontSize: 9, fill: "#475569"}],

               s0w0: ["Circle", {left: 50, top: 50, radius: 10,
                                  fill: "#e5e7eb", stroke: "#94a3b8", strokeWidth: 1}],
               s0w1: ["Circle", {left: 88, top: 50, radius: 10,
                                  fill: "#e5e7eb", stroke: "#94a3b8", strokeWidth: 1}],
               s1w0: ["Circle", {left: 50, top: 80, radius: 10,
                                  fill: "#e5e7eb", stroke: "#94a3b8", strokeWidth: 1}],
               s1w1: ["Circle", {left: 88, top: 80, radius: 10,
                                  fill: "#e5e7eb", stroke: "#94a3b8", strokeWidth: 1}],
               s2w0: ["Circle", {left: 50, top: 110, radius: 10,
                                  fill: "#e5e7eb", stroke: "#94a3b8", strokeWidth: 1}],
               s2w1: ["Circle", {left: 88, top: 110, radius: 10,
                                  fill: "#e5e7eb", stroke: "#94a3b8", strokeWidth: 1}],
               s3w0: ["Circle", {left: 50, top: 140, radius: 10,
                                  fill: "#e5e7eb", stroke: "#94a3b8", strokeWidth: 1}],
               s3w1: ["Circle", {left: 88, top: 140, radius: 10,
                                  fill: "#e5e7eb", stroke: "#94a3b8", strokeWidth: 1}],

               status: ["Text", "reset/idle",
                        {left: 130, top: 58,
                         fontSize: 10,
                         fill: "#6b7280"}],
               selected: ["Text", "set=0 way=0",
                          {left: 130, top: 78,
                           fontSize: 9,
                           fill: "#6b7280"}],
               counts: ["Text", "hits=0 misses=0",
                        {left: 130, top: 98,
                         fontSize: 9,
                         fill: "#2563eb"}],
               legend0: ["Text", "blue=valid",
                         {left: 130, top: 128,
                          fontSize: 9,
                          fill: "#2563eb"}],
               legend1: ["Text", "green=hit",
                         {left: 130, top: 146,
                          fontSize: 9,
                          fill: "#22c55e"}],
               legend2: ["Text", "orange=fill",
                         {left: 130, top: 164,
                          fontSize: 9,
                          fill: "#f97316"}]
            },
            render() {
               let event = '$icache_viz_event'.asInt(0)
               let set = '$icache_viz_selected_set'.asInt(0)
               let way = '$icache_viz_selected_way'.asInt(0)
               let valids = '$icache_viz_all_valids'.asInt(0)
               let hits = '$icache_hit_count'.asInt(0)
               let misses = '$icache_miss_count'.asInt(0)

               let cells = [
                  this.obj.s0w0, this.obj.s0w1,
                  this.obj.s1w0, this.obj.s1w1,
                  this.obj.s2w0, this.obj.s2w1,
                  this.obj.s3w0, this.obj.s3w1
               ]

               for (let i = 0; i < 8; i++) {
                  let valid = (valids >> i) & 1
                  cells[i].set({fill: valid ? "#2563eb" : "#e5e7eb",
                                stroke: "#94a3b8",
                                strokeWidth: 1})
               }

               let selected_cell = set * 2 + way

               if (event === 1 || event === 2) {
                  cells[selected_cell].set({fill: "#22c55e",
                                            stroke: "#bbf7d0",
                                            strokeWidth: 3})
               } else if (event === 3 || event === 4) {
                  cells[selected_cell].set({fill: "#f97316",
                                            stroke: "#fed7aa",
                                            strokeWidth: 3})
               }

               let msg =
                  event === 1 ? "hit way 0" :
                  event === 2 ? "hit way 1" :
                  event === 3 ? "miss fill way 0" :
                  event === 4 ? "miss fill way 1" :
                                "reset/idle"

               let eventColor =
                  event === 1 || event === 2 ? "#22c55e" :
                  event === 3 || event === 4 ? "#f97316" :
                                               "#6b7280"

               this.obj.status.set("text", msg)
               this.obj.status.set("fill", eventColor)

               this.obj.selected.set("text", `set=${set} way=${way}`)
               this.obj.selected.set("fill", eventColor)

               this.obj.counts.set("text", `hits=${hits} misses=${misses}`)
               this.obj.counts.set("fill", "#2563eb")
            },
            where: {left: -300, top: 350, width: 440, height: 308}

   m4+cpu_viz(@4)
\SV
   endmodule

