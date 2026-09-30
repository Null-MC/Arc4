public module text;


	static const uint _A     = 0x747f18c4u;
	static const uint _B     = 0xf47d18f8u;
	static const uint _C     = 0x746108b8u;
	static const uint _D     = 0xf46318f8u;
	static const uint _E     = 0xfc39087cu;
	static const uint _F     = 0xfc390840u;
	static const uint _G     = 0x7c2718b8u;
	static const uint _H     = 0x8c7f18c4u;
	static const uint _I     = 0x71084238u;
	static const uint _J     = 0x084218b8u;
	static const uint _K     = 0x8cb928c4u;
	static const uint _L     = 0x8421087cu;
	static const uint _M     = 0x8eeb18c4u;
	static const uint _N     = 0x8e6b38c4u;
	static const uint _O     = 0x746318b8u;
	static const uint _P     = 0xf47d0840u;
	static const uint _Q     = 0x74631934u;
	static const uint _R     = 0xf47d18c4u;
	static const uint _S     = 0x7c1c18b8u;
	static const uint _T     = 0xf9084210u;
	static const uint _U     = 0x8c6318b8u;
	static const uint _V     = 0x8c62a510u;
	static const uint _W     = 0x8c635dc4u;
	static const uint _X     = 0x8a88a8c4u;
	static const uint _Y     = 0x8a884210u;
	static const uint _Z     = 0xf844447cu;
	static const uint _a     = 0x0382f8bcu;
	static const uint _b     = 0x85b318f8u;
	static const uint _c     = 0x03a308b8u;
	static const uint _d     = 0x0b6718bcu;
	static const uint _e     = 0x03a3f83cu;
	static const uint _f     = 0x323c8420u;
	static const uint _g     = 0x03e2f0f8u;
	static const uint _h     = 0x842d98c4u;
	static const uint _i     = 0x40308418u;
	static const uint _j     = 0x080218b8u;
	static const uint _k     = 0x4254c524u;
	static const uint _l     = 0x6108420cu;
	static const uint _m     = 0x06ab5ac4u;
	static const uint _n     = 0x07a318c4u;
	static const uint _o     = 0x03a318b8u;
	static const uint _p     = 0x05b31f40u;
	static const uint _q     = 0x03671784u;
	static const uint _r     = 0x05b30840u;
	static const uint _s     = 0x03e0e0f8u;
	static const uint _t     = 0x211c420cu;
	static const uint _u     = 0x046318bcu;
	static const uint _v     = 0x04631510u;
	static const uint _w     = 0x04635abcu;
	static const uint _x     = 0x04544544u;
	static const uint _y     = 0x0462f0f8u;
	static const uint _z     = 0x07c4447cu;
	static const uint _0     = 0x746b58b8u;
	static const uint _1     = 0x23084238u;
	static const uint _2     = 0x744c88fcu;
	static const uint _3     = 0x744c18b8u;
	static const uint _4     = 0x19531f84u;
	static const uint _5     = 0xfc3c18b8u;
	static const uint _6     = 0x3221e8b8u;
	static const uint _7     = 0xfc422210u;
	static const uint _8     = 0x745d18b8u;
	static const uint _9     = 0x745e1130u;
	static const uint _space = 0x0000000u;
	static const uint _dot   = 0x000010u;
	static const uint _minus = 0x0000e000u;
	static const uint _comma = 0x00000220u;
	static const uint _colon = 0x02000020u;

	// Additional characters added by WoMspace <3
	static const uint _under = 0x000007Cu;  // _
	static const uint _quote = 0x52800000u; // "
	static const uint _exclm = 0x21084010u; // !
	static const uint _gt    = 0x02082220u; // >
	static const uint _lt    = 0x00888208u; // <
	static const uint _opsqr = 0x3908421Cu; // [
	static const uint _clsqr = 0xE1084270u; // ]
	static const uint _opprn = 0x11084208u; // (
	static const uint _clprn = 0x41084220u; // )
	static const uint _block = 0xFFFFFFFCu; // █
	static const uint _copyr = 0x03AB9AB8u; // ©️

	static const int charWidth   = 5;
	static const int charHeight  = 6;
	static const int charSpacing = 1;
	static const int lineSpacing = 1;

	static const int2 charSize  = int2(charWidth, charHeight);
	static const int2 spaceSize = charSize + int2(charSpacing, lineSpacing);

	// Text renderer

	static struct Text {
		float4 result;     // Output color from the text renderer
		float4 fgCol;      // Text foreground color
		float4 bgCol;      // Text background color
		int2 fragPos;   // The position of the fragment (can be scaled to adjust the size of the text)
		int2 textPos;   // The position of the top-left corner of the text
		int2 charPos;   // The position of the next character in the text
		int base;        // Number base
		int fpPrecision; // Number of decimal places to print
	} textData;

	// Fills the global text object with default values
	void beginText(int2 fragPos, int2 textPos) {
		textData.result      = float4(0.0);
		textData.fgCol       = float4(1.0);
		textData.bgCol       = float4(0.0, 0.0, 0.0, 0.6);
		textData.fragPos     = fragPos;
		textData.textPos     = textPos;
		textData.charPos     = int2(0);
		textData.base        = 10;
		textData.fpPrecision = 2;
	}

	// Applies the rendered text to the fragment
	void endText(inout float3 fragColor) {
		fragColor = lerp(fragColor.rgb, textData.result.rgb, textData.result.a);
	}

namespace Print {

	public void Char(uint character) {
		int2 pos = textData.fragPos - textData.textPos - spaceSize * textData.charPos * int2(1, -1) + int2(0, spaceSize.y);

		uint index = uint(charWidth - pos.x + pos.y * charWidth + 1);

		// Draw background
		if (all(clamp(pos, int2(0), spaceSize - 1) == pos))
			textData.result = lerp(textData.result, textData.bgCol, textData.bgCol.a);

		// Draw character
		if (all(clamp(pos, int2(0), charSize - 1) == pos))
			textData.result = lerp(textData.result, textData.fgCol, textData.fgCol.a * float(character >> index & 1u));

		// Advance to next character
		textData.charPos.x++;
	}

	public void String(uint[] characters) {
		for (int i = 0; i < characters.getCount(); ++i)
			Char(characters[i]);
	}

	public void UnsignedInt(uint value, int len) {
		const uint[36] digits = uint[](
			_0, _1, _2, _3, _4, _5, _6, _7, _8, _9,
			_a, _b, _c, _d, _e, _f, _g, _h, _i, _j,
			_k, _l, _m, _n, _o, _p, _q, _r, _s, _t,
			_u, _v, _w, _x, _y, _z
		);

		// Advance to end of the number
		textData.charPos.x += len - 1;

		// Write number backwards
		for (int i = 0; i < len; ++i) {
			Char(digits[int(value) % textData.base]);
			value /= uint(textData.base);
			textData.charPos.x -= 2;
		}

		// Return to end of the number
		textData.charPos.x += len + 1;
	}

	public void UnsignedInt(uint value) {
		float logValue = log(float(value)) + 1e-6;
		float logBase  = log(float(textData.base));

		int len = int(ceil(logValue / logBase));
			len = max(len, 1);

		UnsignedInt(value, len);
	}

	void Int(int value) {
		if (value < 0) Char(_minus);
		UnsignedInt(uint(abs(value)));
	}

	void Float(float value) {
		if (value < 0.0) Char(_minus);

		if (isnan(value)) {
			// printString((_N, _a, _N));
			Char(_N);
			Char(_a);
			Char(_N);
		} else if (isinf(value)) {
			// printString((_i, _n, _f));
			Char(_i);
			Char(_n);
			Char(_f);
		} else {
			float i, f = modf(abs(value), i);

			uint integralPart   = uint(i);
			uint fractionalPart = uint(f * pow(float(textData.base), float(textData.fpPrecision)) + 0.5);

			UnsignedInt(integralPart);
			Char(_dot);
			UnsignedInt(fractionalPart, textData.fpPrecision);
		}
	}

	void Bool(bool value) {
		if (value) {
			// String((_t, _r, _u, _e));
			Char(_t);
			Char(_r);
			Char(_u);
			Char(_e);
		} else {
			// String((_f, _a, _l, _s, _e));
			Char(_f);
			Char(_a);
			Char(_l);
			Char(_s);
			Char(_e);
		}
	}

	void Vec2(float2 value) {
		Float(value.x);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		Float(value.y);
	}
	void Vec3(float3 value) {
		Float(value.x);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		Float(value.y);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		Float(value.z);
	}
	void Vec4(float4 value) {
		Float(value.x);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		Float(value.y);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		Float(value.z);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		Float(value.w);
	}

	void Ivec2(int2 value) {
		Int(value.x);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		Int(value.y);
	}
	void Ivec3(int3 value) {
		Int(value.x);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		Int(value.y);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		Int(value.z);
	}
	void Ivec4(int4 value) {
		Int(value.x);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		Int(value.y);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		Int(value.z);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		Int(value.w);
	}

	void Uvec2(uint2 value) {
		UnsignedInt(value.x);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		UnsignedInt(value.y);
	}
	void Uvec3(uint3 value) {
		UnsignedInt(value.x);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		UnsignedInt(value.y);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		UnsignedInt(value.z);
	}
	void Uvec4(uint4 value) {
		UnsignedInt(value.x);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		UnsignedInt(value.y);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		UnsignedInt(value.z);
		// String((_comma, _space));
		Char(_comma);
		Char(_space);
		UnsignedInt(value.w);
	}

	void Line() {
		textData.charPos.x = 0;
		++textData.charPos.y;
	}

}
