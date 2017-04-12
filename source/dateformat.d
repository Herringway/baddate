module dateformat;

import std.algorithm;
import std.conv : to;
import std.ascii : isDigit;
import std.range : front, popFront, empty;
import std.datetime;
import std.format;
import std.meta;
import std.typecons : tuple;

auto splitSequence(string str) {
	string[] chunks;
	bool isEscape;
	string currentChunk;
	foreach (character; str) {
		if (isEscape || (!isEscape && character == '%')) {
			if (isEscape) {
				currentChunk ~= character;
				chunks ~= currentChunk;
				currentChunk = "";
			} else {
				if (currentChunk != "") {
					chunks ~= currentChunk;
				}
				currentChunk = "";
				currentChunk ~= character;
			}
			isEscape = !isEscape;
			continue;
		}
		currentChunk ~= character;
	}
	if (currentChunk != "") {
		chunks ~= currentChunk;
	}
	return chunks;
}
unittest {
	assert(splitSequence("%m-%d-%y") == ["%m", "-", "%d", "-", "%y"]);
	assert(splitSequence("%m-%%-%y") == ["%m", "-", "%%", "-", "%y"]);
	assert(splitSequence("-") == ["-"]);
	assert(splitSequence("--") == ["--"]);
}
auto formattedDateTime(string fmt)(string input) {
	alias dateComponents = AliasSeq!("%d", "%m", "%y", "%Y");
	alias timeComponents = AliasSeq!("%H", "%M", "%S", "%I");
	alias timezoneComponents = AliasSeq!("%Z");
	alias fracSecComponents = AliasSeq!("%s");
	enum seq = splitSequence(fmt);
	static if (seq.canFind(timezoneComponents)) {
		Duration offset;
	}
	static if (seq.canFind(fracSecComponents)) {
		FracSec fraction;
		static if (!seq.canFind(timeComponents) && !seq.canFind(timezoneComponents)) {
			int second;
		}
	}
	static if (seq.canFind(dateComponents) || seq.canFind(timezoneComponents)) {
		ubyte day = 1;
		Month month = Month.jan;
		short year = 1;
	}
	static if (seq.canFind(timeComponents) || seq.canFind(timezoneComponents)) {
		int second = 0;
		int minute = 0;
		int hour = 0;
	}
	foreach (portion; aliasSeqOf!seq) {
		static if (portion == "%d") {
			formattedRead(input, "%s", day);
		} else static if (portion == "%m") {
			ubyte monthRep;
			formattedRead(input, "%s", monthRep);
			month = cast(Month)monthRep;
		} else static if (portion == "%y") {
			formattedRead(input, "%s", year);
			year = cast(short)((year > 69) ? year + 1900 : year + 2000);
		} else static if (portion == "%Y") {
			formattedRead(input, "%s", year);
		} else static if (portion == "%H") {
			formattedRead(input, "%s", hour);
		} else static if (portion == "%M") {
			formattedRead(input, "%s", minute);
		} else static if (portion == "%S") {
			formattedRead(input, "%s", second);
		} else static if (portion == "%s") {
			bool negative;
			if (input.startsWith('-')) {
				input.popFront();
				negative = true;
			}
			while (input.startsWith!isDigit) {
				second *= 10;
				second += input.front - '0';
				input.popFront();
			}
			if (input.startsWith('.')) {
				int hnsecs;
				int digitsRead;
				input.popFront();
				while (input.startsWith!isDigit) {
					hnsecs *= 10;
					hnsecs += input.front - '0';
					digitsRead++;
					input.popFront();
				}
				hnsecs *= 10^^(7-digitsRead);
				fraction.hnsecs = hnsecs;
			}
			second *= negative ? -1 : 1;
		} else static if (portion == "%Z") {
			if (input.front == 'Z') {
				offset = Duration.init;
			} else if (input.front.among('+', '-')) {
				dchar[2] hourOffset;
				immutable sign = input.front;
				input.popFront();
				hourOffset[0] = input.front;
				input.popFront();
				hourOffset[1] = input.front;
				input.popFront();
				if (sign == '+') {
					offset -= hourOffset.to!byte.hours;
				} else {
					offset += hourOffset.to!byte.hours;
				}

				//colons are optional and meaningless
				if (!input.empty && (input.front == ':')) {
					input.popFront();
				}


				if (!input.empty && input.front.isDigit) {
					dchar[2] minuteOffset;
					minuteOffset[0] = input.front;
					input.popFront();
					minuteOffset[1] = input.front;
					if (sign == '+') {
						offset -= minuteOffset.to!byte.minutes;
					} else {
						offset += minuteOffset.to!byte.minutes;
					}
				}
			}
		} else {
			formattedRead(input, portion);
		}
	}

	static if (seq.canFind(timezoneComponents)) {
		immutable tz = new immutable SimpleTimeZone(offset, "");
		static if (seq.canFind(fracSecComponents)) {
			return SysTime(DateTime(year, month, day, hour, minute, second), fraction, tz);
		} else {
			return SysTime(DateTime(year, month, day, hour, minute, second), tz);
		}
	} else static if (seq.canFind(dateComponents) && seq.canFind(timeComponents)) {
		static if (seq.canFind(fracSecComponents)) {
			return tuple(DateTime(year, month, day, hour, minute, second), fraction);
		} else {
			return DateTime(year, month, day, hour, minute, second);
		}
	} else static if (seq.canFind(dateComponents)) {
		static if (seq.canFind(fracSecComponents)) {
			return tuple(Date(year, month, day), fraction);
		} else {
			return Date(year, month, day);
		}
	} else static if (seq.canFind(timeComponents)) {
		static if (seq.canFind(fracSecComponents)) {
			return tuple(TimeOfDay(hour, minute, second), fraction);
		} else {
			return TimeOfDay(hour, minute, second);
		}
	} else static if (seq.canFind(fracSecComponents)) {
		return tuple(second, fraction);
	} else static assert(0, "No time components found in format string");
}
///
@safe unittest {
	import dunit.toolkit : assertEqual;
	formattedDateTime!"%m-%d-%y"("03-01-94").assertEqual(Date(1994, 03, 01));

	formattedDateTime!"%H:%M:%S"("12:34:53").assertEqual(TimeOfDay(12, 34, 53));

	formattedDateTime!"%m-%d-%y %H:%M:%S"("03-01-94 12:34:53").assertEqual(DateTime(Date(1994, 03, 01), TimeOfDay(12, 34, 53)));

	formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 +0000").assertEqual(SysTime(DateTime(Date(1994, 03, 01), TimeOfDay(12, 34, 53)), UTC()));

	formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 +0100").assertEqual(SysTime(DateTime(Date(1994, 03, 01), TimeOfDay(13, 34, 53)), UTC()));

	formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 -0100").assertEqual(SysTime(DateTime(Date(1994, 03, 01), TimeOfDay(11, 34, 53)), UTC()));

	formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 +00:00").assertEqual(SysTime(DateTime(Date(1994, 03, 01), TimeOfDay(12, 34, 53)), UTC()));

	formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 +01:00").assertEqual(SysTime(DateTime(Date(1994, 03, 01), TimeOfDay(13, 34, 53)), UTC()));

	formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 -01:00").assertEqual(SysTime(DateTime(Date(1994, 03, 01), TimeOfDay(11, 34, 53)), UTC()));

	formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 +00").assertEqual(SysTime(DateTime(Date(1994, 03, 01), TimeOfDay(12, 34, 53)), UTC()));

	formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 +01").assertEqual(SysTime(DateTime(Date(1994, 03, 01), TimeOfDay(13, 34, 53)), UTC()));

	formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 -01").assertEqual(SysTime(DateTime(Date(1994, 03, 01), TimeOfDay(11, 34, 53)), UTC()));

	formattedDateTime!"%Y-%m-%d %H:%M:%s"("2013-09-28 02:07:11.633883").assertEqual(tuple(DateTime(2013, 09, 28, 02, 07, 11), FracSec.from!"usecs"(633_883)));

	formattedDateTime!"%Y-%m-%d %H:%M:%S"("2007-11-28 04:00:27").assertEqual(DateTime(2007, 11, 28, 04, 00, 27));

	formattedDateTime!"%Y-%m-%d %H:%M:%S"("2016-01-15 08:25:20").assertEqual(DateTime(2016, 01, 15, 08, 25, 20));
}