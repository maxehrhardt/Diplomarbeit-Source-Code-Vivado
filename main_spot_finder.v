`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: TU Dresden
// Engineer: Maximilian Ehrhardt
// 
// Create Date: 25.04.2017 15:05:01
// Design Name: 
// Module Name: main_spot_finder
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
/*
    This block reads pixel data from the seperate spot finder block RAM. The data is analyzed for spots and the area where the spot can be found is the output.
    
    Internal Behavior:
    state machine:
    - State 0:  put memory address on block RAM
    - State 1:  waiting state, brings two clock cycles between aplplying the mem address and reading the data
    - State 2:  read data from block RAM and analyze the data
    - State 3:  write the ROIs from internal buffer to output register
    - State 4:  resets all the variables
*/
//////////////////////////////////////////////////////////////////////////////////


module main_spot_finder(
    clk_in,
    PAR_CLK,
    data_in,
    cam_kernels_x,
    cam_lines_y,
    reset,
    mem_address,
    num_rois,
    ROIs_output,
    analysis_rdy,
    stateMachine,
    image_saved,
    //Used for debugging
    pixel_value,
    kernel_index,
    line_index,
    is_in_roi,
    pixel_index,
    brightness_threshold,
    ROI_width_x,
    ROI_height_y,
    num_rois_max
    
    
);

//### parameters
//parameter brightness_threshold=127;
//parameter ROI_width_x=7;
//parameter ROI_height_y=7;
//parameter num_rois_max=10;
input wire [7:0] brightness_threshold;
input wire [15:0] ROI_width_x;
input wire [16:0] ROI_height_y;
input wire [7:0] num_rois_max;

//### interface 
input   wire            clk_in;
input   wire            PAR_CLK;

input   wire            reset;

input   wire    [255:0] data_in;

input   wire    [15:0]  cam_kernels_x;

input   wire    [15:0]  cam_lines_y;

input   wire            image_saved; //inidcates if a full image is saved to the BRAM

output  reg     [13:0]  mem_address;
initial                 mem_address=0;

//output  reg     [num_rois_max*4*10-1:0] ROIs_output;
output  reg     [255*4*10-1:0] ROIs_output;

output  reg             analysis_rdy;   //Is set to 1 when complete analysis of 1 image is completed
initial                 analysis_rdy=0;


//### internal register
output reg     [7:0]   stateMachine;
initial         stateMachine = 4;

output reg     [13:0]  kernel_index; 
initial         kernel_index=0;

output reg     [13:0]  line_index; 
initial         line_index=0;

output reg     [5:0]   pixel_index; //Used to index the pixel in the kernel that is currently observed; Value=0...31, but more bits where used to avoid errors due to overflow
initial         pixel_index=0;

reg     [7:0]   i;  //Loop iterator
initial         i=0;
reg     [7:0]   k;  //Loop iterator
initial         k=0;

output reg     [7:0]   pixel_value; //8Bit value of currently observed pixel



//Array that holds all the regions of Interest (ROI) for the spots [ROI_x_Start/ROI_y_Start/ROI_x_End/ROI_y_End]
//ROI_Start defines the position of the top left corner of the ROI rectangle, ROI_End the bottom right corner
//Positions can have a maximum value of 649 thats why 10 bits for each value are reserved, Memory for 10 ROIs is declared
reg [9:0] ROIs_buffer [3:0][num_rois_max-1:0];

//Buffer variables for ROI
reg [9:0] ROI_x_Start; 
reg [9:0] ROI_y_Start;
reg [9:0] ROI_x_End;
reg [9:0] ROI_y_End;
//Number of ROIs found
output reg [7:0] num_rois;
initial num_rois=0;
//Variable used to indicate whether pixel is in ROI 0 for false, 1 for true
output reg is_in_roi;
initial is_in_roi=0;

//Position of currently observed pixel in image, [0/0] is in left top corner, x horizontal, y vertical
reg [9:0] pos_x;
reg [9:0] pos_y;

//Maximum position value possible in image, VGA Standard is used, 640x480 pixel
reg [9:0] pos_x_max;
//initial pos_x_max=cam_kernels_x*32-1;
reg [9:0] pos_y_max;
//initial pos_y_max=cam_lines_y-1;


//### code start
always @(posedge clk_in) begin
    
    //check for reset
    if(reset == 1) begin
        stateMachine=4;
    end
    else begin
        //Initial state
        if(stateMachine == 0) begin
            stateMachine = stateMachine + 1;
        end
        //Waiting state, to wait two clock cycles between applying the mem_address and reading tha data
        else if(stateMachine ==1) begin
            stateMachine = stateMachine + 1;
        end
        //Read data from memory and analyze for spots
        else if(stateMachine ==2) begin
            //Check 1 pixel per clock cycle           
            pos_y=line_index;                        
            pos_x=kernel_index*32+pixel_index;             
            pixel_value=data_in[8*pixel_index +: 8];
            
            if(pixel_value>brightness_threshold) begin
                //Iterate through the ROIs already acquired, to check whether current pixel is already in a ROI
                is_in_roi=0;
                for (k = 0;k<num_rois ;k=k+1 ) begin
                        if (pos_x>=ROIs_buffer[0][k] && pos_y>=ROIs_buffer[1][k] && pos_x<=ROIs_buffer[2][k] && pos_y<=ROIs_buffer[3][k]) begin
                            is_in_roi=1;
                        end
//                    if (pos_x>=ROIs_output[40*num_rois +: 10] && pos_y>=ROIs_output[40*num_rois+10 +: 10] && pos_x<=ROIs_output[40*num_rois+20 +: 10] && pos_y<=ROIs_output[40*num_rois+30 +: 10]) begin
//                        is_in_roi=1;
//                    end
                end
                
                if (is_in_roi!=1) begin
                    //Set new ROI around current pixel
                    if (pos_x<ROI_width_x>>1) begin
                    ROI_x_Start=0;
                    end else begin
                    ROI_x_Start=pos_x-ROI_width_x>>1;
                    end
                
                    if (pos_y<ROI_height_y>>1) begin
                    ROI_y_Start=0;
                    end else begin
                    ROI_y_Start=pos_y-ROI_height_y>>1;
                    end
            
                    if (pos_x>pos_x_max-ROI_width_x>>1) begin
                    ROI_x_End=pos_x_max;
                    end else begin
                    ROI_x_End=pos_x+ROI_width_x>>1;
                    end
            
                    if (pos_y>pos_y_max-ROI_height_y>>1) begin
                    ROI_y_End=pos_y_max;
                    end else begin
                    ROI_y_End=pos_y+ROI_height_y>>1;
                    end
            
                    //Write the ROI buffer variables to the ROI_Array
                    
                        ROIs_buffer[0][num_rois]=ROI_x_Start;
                        ROIs_buffer[1][num_rois]=ROI_y_Start;
                        ROIs_buffer[2][num_rois]=ROI_x_End;
                        ROIs_buffer[3][num_rois]=ROI_y_End;
//                      ROIs_output[40*num_rois +: 40]={ROI_x_Start,ROI_y_Start,ROI_x_End,ROI_y_End};
                      
            
                    //Increase number of found ROIs
                    num_rois=num_rois+1;
                    
                    //Jump over the next pixel, because they are definitely in a ROI
                    //pixel_index=pixel_index+ROI_width_x>>1+1;                        
                end
            end
            
            
            
            
            if (num_rois>=num_rois_max) begin
                stateMachine=3;
            end
            //Check whether all pixels of current kernel have been observed
            else if (pixel_index>=31) begin     
                // Increment the memory address, kernel_index and line_index
                mem_address = mem_address + 1;
                
                //At the end of a line the kernel_index is reset and the line_index is increased by one
                if(kernel_index==cam_kernels_x-1) begin
                    kernel_index=0;
                    line_index=line_index+1;
                end
                else begin
                    kernel_index = kernel_index+1;
                end                                                              
                                               
                
                
                // Set StateMachine to initial state
                stateMachine=0;
                
                // Reset pixel_index
                pixel_index=0;
                
                //Check whether all pixels have been analyzed
                if(mem_address>cam_kernels_x*cam_lines_y-1) begin
                    stateMachine=3;       
                end
            end
            else begin
                //Increase pixel_index and stay in the state
                stateMachine=2;
                pixel_index=pixel_index+1;
            end           
        end
        //state to copy the ROIs from buffer to output register
        else if(stateMachine==3) begin
            //Copy all ROIs to Output Buffer
            for (i = 0;i<num_rois_max ;i=i+1 ) begin
                ROIs_output[40*i +: 40]={ROIs_buffer[0][i],ROIs_buffer[1][i],ROIs_buffer[2][i],ROIs_buffer[3][i]};
            end
            analysis_rdy=1;
            stateMachine=4;
        end
        //State that resets the analysis
        else if(stateMachine==4) begin
            
            if (image_saved==1) begin
                stateMachine = 0;        
                mem_address=0;
                kernel_index=0;
                line_index=0;
                pixel_index=0;
                
                //reset the ROIs array
                for (i=0;i<num_rois_max;i=i+1) begin
                    for (k=0;k<4;k=k+1) begin
                        ROIs_buffer[k][i]=10'b0;
                    end          
                end
        
                num_rois=0;       
                ROIs_output=num_rois_max*4*10'b0; 
                analysis_rdy=0;
                
                pos_x_max=cam_kernels_x*32-1;
                pos_y_max=cam_lines_y-1;
            end
            else begin
                stateMachine=4;
            end

        end
        
        

        
    end

end

endmodule
