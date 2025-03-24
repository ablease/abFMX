
#include <klang.h>
using namespace klang::optimised;

signal soft_clip(signal x, param c) {
	if(x >= 0) {
		return (1 + c) * x / (1 + c * x);
	} else { 
		return (1 + c) * x / (1 - c * x);
	}
}

struct ModEnv {
	float attack;
	float decay;
	float sustain;
	float release;
	
	void set(float a, float d, float s, float r, param xtrmMod){
		if(xtrmMod==1) {
			attack = a * 10;
			decay = d * 10;
			sustain = s * 10;
			release = r * 10;
		} else {
			attack = a;
			decay = d;
			sustain = s;
			release = r;
		}
	}
};

struct AbDistortion : Stereo::Modifier {
	LPF preFilter;
	HPF dcFilter;
	LPF postFilter;
	param preFilterCutoff = 0;
	param postFilterCutoff = 0;
	param shape = 0;
	param gain = 1;
	
	void set(param s, param g, param preF, param postF) {
		shape = s;
		gain = g;
		preFilterCutoff = preF;
		postFilterCutoff = postF;
	}
	
	void process() {	
		stereo::signal soft_mix = {0, 0};

		soft_mix.l = in.l>> preFilter(preFilterCutoff);
		soft_mix.r = in.r>> preFilter(preFilterCutoff);
		
		soft_mix.l = soft_clip(in.l, shape);
		soft_mix.r = soft_clip(in.r, shape);

		soft_mix.l = soft_mix.l * gain;
		soft_mix.r = soft_mix.r * gain;
		
		// DC filter
		soft_mix.l = soft_mix.l >> dcFilter(30);
		soft_mix.r = soft_mix.r >> dcFilter(30);
		
		// post filtering
		soft_mix.l = soft_mix.l >> postFilter(postFilterCutoff);
		soft_mix.r = soft_mix.r >> postFilter(postFilterCutoff);
		
		soft_mix.l >> out.l;
		soft_mix.r >> out.r;
	}
};

struct myOperator : Operator<Sine> {
	LPF lpf;
	
	myOperator() {
		lpf.set(100);
	}
	
	
	void setLPF(param cutoff){
	
	}
	
	void process() {
		Operator<Sine>::process();
		out >> lpf >> out;
	};
	
};

// Normalize values in the range -1 to 1, to the range 0  to 1. 
signal normal(signal x) {
	param min = -1;
	param max = 1;
	return (x - min) / (max - min);
}

// LFO used for Amplitude Modulation
struct LFO : Stereo::Generator {
	Sine sin;
	param amount;
	param depth;
	
	void set(param f, param a, param d){		
		sin(f);
		amount = a;
		depth = d;
	}
	
	void process() {
		normal(sin * amount * depth) >> out.l;
		normal(sin * amount * depth) >> out.r;
	}
};

# define N 3
struct abFMX : Stereo::Synth {
	AbDistortion distortion;
	LFO lfo;
	
	struct Harmonic : Oscillator {
		Sine osc[N];
		Envelope env; 
		signal mix = 0;
		
		void set(relative phase){
			for(int o=0; o<N; o++)
				osc[o].set(phase);
		}
		
		void set(param frequency){
			for(int o=0; o<N; o++)
				osc[o].set(frequency * (o+1));
		}

		void process() {
			mix = 0;
			for(int o=0; o<N; o++)
				mix += osc[o] * 0.1;
			 
			mix* env++ >> out;
		}
	};
	
	struct abFMXNote : public Mono::Note {
		Operator<Harmonic> op1;
		myOperator op2;
		myOperator op3;
		myOperator op4;
		
		ModEnv op2Mod;
		ModEnv op3Mod;
		ModEnv op4Mod;
		
		event on(Pitch pitch, Amplitude velocity) {
			const param f = pitch -> Frequency;
			
			param A = controls[8] + 0.001;
			param D = controls[9] + 0.001;
			param S = controls[10];
			
			param loop = controls[38];
			
			op2Mod.set(controls[12], controls[13], controls[14], controls[15], controls[37]);
			op3Mod.set(controls[16], controls[17], controls[18], controls[19], controls[37]);
			op4Mod.set(controls[20], controls[21], controls[22], controls[23], controls[37]);
			
			op1.set(f * controls[0]);//, 0);
			op1.env = { { 0, 0 }, { A,   controls[1] }, 
			                      { A+D, controls[1] * S } };
			op1.env.setLoop(2, 2);
						
			op2.set(f * controls[2], 0);
			op2.env = { 
				{ 0, op2Mod.attack }, 
				{ op2Mod.attack, controls[3]}, 
				{ op2Mod.attack+op2Mod.decay, controls[3] * op2Mod.sustain}, 
				{ op2Mod.attack+op2Mod.decay+op2Mod.sustain, controls[3] * op2Mod.release} 
			};
			
			
			op3.set(f * controls[4], 0);
			op3.env = { 
				{ 0, op3Mod.attack },
				{ op3Mod.attack, controls[5]},
				{ op3Mod.attack+op3Mod.decay, controls[5] * op3Mod.sustain},
				{ op3Mod.attack+op3Mod.decay+op3Mod.sustain, controls[3] * op3Mod.release} 
			};
			
			
			op4.set(f * controls[6], 0);
			op4.env = { 
				{ 0, op4Mod.attack },
				{ op4Mod.attack, controls[5]},
				{ op4Mod.attack+op4Mod.decay, controls[7] * op4Mod.sustain},
				{ op4Mod.attack+op4Mod.decay+op4Mod.sustain, controls[3] * op4Mod.release} 
			 };
			
			
			if(loop==1) {
				op2.env.setLoop(1, 3);
				op3.env.setLoop(1, 3);
				op4.env.setLoop(1, 3);
			}
		}	

		event off(Amplitude velocity) {
			op1.env.release(controls[7]);
		}

		void process() {
			int algo = controls[34];
			
			signal mix = 0;
			switch(algo){
			case 0: // op4>op3>op2>op1
				(op4 >> op3 >> op2 >> op1) >> out;
				break;
			case 1: // op4+op3+op2>op1
				((op4 + op3 + op2) >> op1) >> out;
				break;
			case 2: // op4>op3+op2>op1
				mix = op3 + op2;
				(op4 >> mix >> op1) >> out;
				break;
			case 3: // op4+op2>op3>op1
				mix = op4+op2;
				(mix >> op3 >> op1) >> out;
				break;
			}
			
			if (op1.env.finished())
				stop();
		}
	};

	abFMX() {
		controls = {
			{ "OP1", Dial("Ratio", 0.01, 10, 2, { 20,40,40,60 } ),						//0  x, y, w, h
			         Dial("Depth", 0, 10, 0.5, { 65,40,40,60 } ) },						//1
			
			{ "OP2", Dial("Ratio", 0.01, 10, 1, { 200,40,40,60 }),						//2
			         Dial("Depth", 0, 10, 0.5, { 245,40,40,60 }) },						//3
			
			{ "OP3", Dial("Ratio", 0.01, 10, 1, { 20,150,40,60 }), 						//4
			         Dial("Depth", 0, 10, 0.5, { 65,150,40,60 }) }, 					//5
			         
			{ "OP4", Dial("Ratio", 0.01, 10, 1, { 200,150,40,60 }), 					//6
			         Dial("Depth", 0, 10, 0.5, { 245,150,40,60 }) }, 					//7
						
			{ "AMP", Slider("A", 0,2,0, { 125,40,10,60 } ), 							//8
			         Slider("D", 0,2,0.5, { 140,40,10,60 } ), 							//9
			         Slider("S", 0,2,1.0, { 155,40,10,60 } ), 							//10
			         Slider("R", 0,2,0.5, { 170,40,10,60 } ), },						//11
			
			{ "op2Mod", Slider("A", 0,2,0.5, { 300,40,10,60 } ), 						//12
						Slider("D", 0,2,0.5, { 315,40,10,60 } ), 						//13
						Slider("S", 0,2,1.0, { 330,40,10,60 } ), 						//14
						Slider("R", 0,2,0.5, { 345,40,10,60 } ), },						//15
						
			{ "op3Mod", Slider("A", 0,2,0.5, { 120,150,10,60 } ), 						//16
						Slider("D", 0,2,0.5, { 135,150,10,60 } ), 						//17
						Slider("S", 0,2,1.0, { 150,150,10,60 } ), 						//18
						Slider("R", 0,2,0.5, { 165,150,10,60 } ), },					//19
						
			{ "op4Mod", Slider("A", 0,2,0.5, { 300,150,10,60 } ), 						//20
						Slider("D", 0,2,0.5, { 315,150,10,60 } ), 						//21
						Slider("S", 0,2,1.0, { 330,150,10,60 } ), 						//22
						Slider("R", 0,2,0.5, { 345,150,10,60 } ), },					//23
			
			{ "Distortion", Dial("Shape", 0.0, 50.0, 1.0, { 20,350,30,30 }),			//24
							Dial("Gain", 0.0, 1.0, 0.5, { 70,350,30,30 }),				//25
							Dial("PreFilter", 1, 20000, 10000, { 120,350,30,30 }),		//26
							Dial("PostFilter", 1, 20000, 80000, { 170,350,30,30 }), },	//27
			
			{ "Ping Pong", Dial("Time (L)", 0, 1, 0.12, { 20,260,30,30 }),				//28
			               Dial("Gain (L)", 0, 0.99, 0.75, { 70,260,30,30 }),			//29
			               Dial("Time (R)", 0, 1, 0.23, { 120,260,30,30 }),				//30
			               Dial("Gain (R)", 0, 0.99, 0.83, { 170,260,30,30 }),			//31
			               Dial("Amount", 0, 1, 0.3, { 220,260,30,30 }) },				//32
			
			{ "LFO", Dial("LFO", -1, 1, 0, { 270, 260, 25, 30 } ), 						//33
			 		 Dial("Rate", .1, 3, 1, { 320, 260, 25, 30 } ),   					//34
					 Dial("Depth", 0, 1, 0.1, { 370, 260, 25, 30 } ) }, 				//35
			
			Menu("Algo", { 225,320,150,30 },"op4>op3>op2>op1",                  		//36
			 			 "op4+op3+op2>op1",
			 			 "op4>op3+op2>op1",
			 			 "op4+op2>op3>op1"),
			Toggle("XTRM MOD ENVS", false, { 225,355,75,30 }), 							//37
			Toggle("LOOP ENVS", false, { 305,355,75,30 }),								//38
		};
		
		presets = {
			{ "Evolving Organ", { 2.000, 0.500, 1.000, 0.500, 1.000, 0.500, 1.000, 1.000, 2.000, 2.000, 0.276, 0.517, 0.000, 1.345, 1.000, 0.500, 0.000, 0.500, 1.000, 0.500, 0.000, 0.500, 1.000, 0.500, 4.331, 0.794, 15685.626, 15062.558, 0.467, 0.750, 0.755, 0.830, 0.257, -0.391, 2.127, 0.549, 0, 0, 0 } },
			{ "WOW Wobble Bass", { 2.000, 3.000, 6.000, 6.000, 2.000, 4.000, 3.000, 1.000, 0.000, 0.500, 0.103, 0.483, 0.586, 0.586, 0.517, 0.414, 0.310, 0.586, 0.345, 0.379, 0.414, 0.414, 0.448, 0.414, 7.732, 0.456, 6218.583, 12468.272, 0.000, 0.000, 0.000, 0.000, 0.257, -0.938, 2.003, 0.453, 0, 0, 0 } },
			{ "HORROR DRONE", { 1.000, 1.000, 5.000, 4.000, 4.000, 6.000, 5.000, 4.000, 2.000, 2.000, 1.552, 0.000, 2.000, 2.000, 1.552, 0.500, 2.000, 2.000, 1.690, 0.500, 2.000, 2.000, 1.759, 0.500, 5.906, 0.366, 4407.885, 4938.442, 0.467, 0.082, 0.755, 0.186, 0.152, -0.888, 0.558, 0.000, 0, 1, 0 } },
			{ "Endless Mod", { 2.000, 0.500, 1.000, 0.500, 1.000, 2.000, 1.000, 4.000, 0.000, 0.500, 1.000, 0.500, 0.500, 0.500, 1.000, 0.500, 0.500, 0.500, 1.000, 0.500, 0.500, 0.500, 1.000, 0.500, 10.139, 0.328, 10000.000, 7181.106, 0.536, 0.379, 0.696, 0.375, 0.592, 0.000, 1.000, 0.100, 0, 1, 0 } },
		};

		notes.add<abFMXNote>(32);
	}
	
	Stereo::Delay<192000> delay;
	
	void process() {
		distortion.set(controls[24], controls[25], controls[26], controls[27]);
		lfo.set(controls[34], controls[33], controls[35]);
		
		stereo::signal time = { controls[28], controls[30] };
		stereo::signal gain = { controls[29], controls[31] };
		

		signal amount = controls[32];

		(in * lfo) + amount * delay(time * fs) * gain >> distortion >> out;

		
		delay.l << out.r;								  
		delay.r << out.l;
	}
};
