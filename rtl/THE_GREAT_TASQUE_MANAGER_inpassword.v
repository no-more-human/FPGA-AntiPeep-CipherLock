 module THE_GREAT_TASQUE_MANAGER_inpassword(
  input clk,  input rst_n,  input tick1k,  input  key_valid,
  input [3:0] kv,  input [2:0] sys_sta,  output reg [23:0] new,  
      output admin    
 );
 parameter [23:0]ORI={4'h1,4'h2,4'h3,4'h4,4'h5,4'h6};
  reg admin_n;
  always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
     new <= ORI;
     admin_n <= 1'b0;
    end else begin
     if (key_valid) begin
      if (kv == 4'hA && sys_sta == 3'd0)begin
       admin_n <=1'b1;
      end else if(kv == 4'hB)begin
       admin_n <=1'b0;
      end
     end
    end
   end 
       assign admin = admin_n;
 endmodule