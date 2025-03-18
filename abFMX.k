
#include <klang.h>
using namespace klang::optimised;

// TODO - prevent aliasing

struct ModEnv {
	float attack;
	float decay;
	float sustain;
	float release;
	
	void set(float a, float d, float s, float r){
		attack = a;
		decay = d;
		sustain = s;
		release = r;
	}
};

struct AbDelay : Modifier {
	Delay<192000> delay;

	AbDelay() {

		//debug.print("Sample rate = %f", fs.f);
	}


	void prepare() {
		
	}


	void process() {
		param time = 0.5;
		param gain = 0.5;
		signal echo = 0;
		
		
		in + delay(time * fs) * gain >> out;	// output the input plus echo
		delay << out;							// feed the output to the delay
	}
};

struct myOperator : Operator<Sine> {
	LPF lpf;
	
	myOperator() {
		lpf.set(1000);
	}
	
	void setLPF(param cutoff){
	
	}
	
	void process() {
		Operator<Sine>::process();
		out >> lpf >> out;
	};
	
};
# define N 3
struct abFMX : Synth {
	AbDelay abDelay;

	struct Harmonic : Oscillator {
		Sine osc[N];
		Envelope env;
		param mix = 0;
		
		// set function with frequency and phase?
		// set function with 
		
		void set(relative phase){
			for(int o=0; o<N; o++)
				osc[o].set(phase);
		}
		
		void set(param frequency){
			// nyquist limit. maximum frequency is half our sample rate
			//if( frequency > 
			for(int o=0; o<N; o++)
				osc[o].set(frequency * (o+1));
		}

		void process() {
			mix = 0;
			for(int o=0; o<N; o++) // need a nyquist limit check
				mix += osc[o] * 0.1;
			
			mix* env++ >> out;
		}
	};

	struct abFMXNote : public Note {
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
			
			op2Mod.set(controls[12], controls[13], controls[14], controls[15]);
			op3Mod.set(controls[16], controls[17], controls[18], controls[19]);
			op4Mod.set(controls[20], controls[21], controls[22], controls[23]);

			
			op1.set(f * controls[0]);//, 0); // second parameter is detune
			op1.env = { { 0, 0 }, { A,   controls[1] }, 
			                      { A+D, controls[1] * S } };
			op1.env.setLoop(2, 2);
						
			op2.set(f * controls[2], 0);
			op2.env = { { 0, op2Mod.attack }, { op2Mod.attack, controls[3]}, {op2Mod.attack+op2Mod.decay, controls[3] * op2Mod.sustain} };
			
			op3.set(f * controls[4], 0);
			op3.env = { { 0, op3Mod.attack }, { op3Mod.attack, controls[5]}, {op3Mod.attack+op3Mod.decay, controls[5] * op3Mod.sustain} };
			// loop the envelopes
			// op3.env.setLoop();
			// fm processed stereo?? 
			
			op4.set(f * controls[6], 0);
			op4.env = { { 0, op4Mod.attack }, { op4Mod.attack, controls[5]}, {op4Mod.attack+op4Mod.decay, controls[7] * op4Mod.sustain} };
			
		}

		event off(Amplitude velocity) {
			op1.env.release(controls[11]);
		}

		void process() {
			int algo = controls[24];
			
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
				(mix >> op3 >> op1) >>out;
				break;
			}
			
			if (op1.env.finished())
				stop();
		}
	};

	abFMX() {
		controls = {
			{ "OP1", Dial("Ratio", 0.01, 10, 2, { 20,40,40,60 } ),		//0  x, y, w, h
			         Dial("Depth", 0, 10, 0.5, { 65,40,40,60 } ) },		//1
			
			{ "OP2", Dial("Ratio", 0.01, 10, 1, { 20,150,40,60 }),		//2
			         Dial("Depth", 0, 10, 0.5, { 65,150,40,60 }) },		//3
			
			{ "OP3", Dial("Ratio", 0.01, 10, 1, { 125,150,40,60 }), 	//4
			         Dial("Depth", 0, 10, 0.5, { 170,150,40,60 }) }, 	//5
			         
			{ "OP4", Dial("Ratio", 0.01, 10, 1, { 230,150,40,60 }), 	//6
			         Dial("Depth", 0, 10, 0.5, { 275,150,40,60 }) }, 	//7
						
			{ "AMP", Slider("A", 0,1,0.5, { 125,40,10,60 } ), 			//8
			         Slider("D", 0,1,0.5, { 140,40,10,60 } ), 			//9
			         Slider("S", 0,1,1.0, { 155,40,10,60 } ), 			//10
			         Slider("R", 0,1,0.5, { 170,40,10,60 } ), },		//11
			         
			{ "op2Mod", Slider("mA", 0,2,0.5, { 20,270,10,60 } ), 		//12
						Slider("mD", 0,2,0.5, { 35,270,10,60 } ), 		//13
						Slider("mS", 0,2,1.0, { 50,270,10,60 } ), 		//14
						Slider("mR", 0,2,0.5, { 65,270,10,60 } ), },	//15
						
			{ "op3Mod", Slider("mA", 0,2,0.5, { 90,270,10,60 } ), 		//16
						Slider("mD", 0,2,0.5, { 105,270,10,60 } ), 		//17
						Slider("mS", 0,2,1.0, { 120,270,10,60 } ), 		//18
						Slider("mR", 0,2,0.5, { 135,270,10,60 } ), },	//19
						
			{ "op4Mod", Slider("mA", 0,2,0.5, { 160,270,10,60 } ), 		//20
						Slider("mD", 0,2,0.5, { 175,270,10,60 } ), 		//21
						Slider("mS", 0,2,1.0, { 190,270,10,60 } ), 		//22
						Slider("mR", 0,2,0.5, { 205,270,10,60 } ), },	//23
						
			{ "Delay", Slider("Time", 0.0, 0.999, 0.5, { 250,270,10,60 } ),
					   Slider("Gain", 0, 1, 0.5, { 280,270,10,60 } ), },

			
			Menu("Algo", { 250,20,100,30 },"op4>op3>op2>op1",
			 			 "op4+op3+op2>op1",
			 			 "op4>op3+op2>op1",
			 			 "op4+op2>op3>op1")
		};
		
//		presets = {
//			{ "EP",          { 1.000, 1.142, 1.000, 1.176, 0.000, 0.500, 1.000, 0.500 } },
//			{ "Harpsichord", { 4.000, 0.500, 6.000, 2.087, 0.000, 0.500, 0.267, 0.457 } },
//			{ "Tubular Bell",{ 2.000, 0.500, 4.000, 2.000, 0.000, 0.810, 0.267, 0.457 } },
//			{ "Tribular Balls",{  10, 1.000, 0.411, 9.931, 0.000, 0.819, 0.000, 0.457 } },
//			{ "Woodwind",    { 2.000, 0.836, 4.000, 1.000, 0.172, 1.000, 0.871, 0.457 } },
//			{ "FM Bass",     { 2.500, 0.836, 0.500, 4.835, 0.000, 0.672, 0.836, 0.457 } },
//			{ "FM Piano",    { 8.000, 0.836, 2.000, 1.528, 0.000, 0.517, 0.103, 0.379 } },
//			{ "Music Box",   { 7.000, 0.500, 8.000, 0.944, 0.000, 0.103, 0.284, 1.000 } },
//			{ "Brass", 	     { 2.000, 0.836, 2.000, 2.025, 0.172, 1.000, 0.871, 0.457 } },
//		};

		notes.add<abFMXNote>(32);
	}
	
	
	
	void processs(){
		in >> abDelay >> out;
	}
};
 
