module baddate;

import std.algorithm;
import std.ascii : isDigit;
import std.conv : to;
import std.datetime;
import std.format;
import std.meta;
import std.range : empty, front, popFront;
import std.typecons : tuple;

private auto splitSequence(string str) {
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
@safe pure unittest {
	assert(splitSequence("%m-%d-%y") == ["%m", "-", "%d", "-", "%y"]);
	assert(splitSequence("%m-%%-%y") == ["%m", "-", "%%", "-", "%y"]);
	assert(splitSequence("-") == ["-"]);
	assert(splitSequence("--") == ["--"]);
}
/++
+ Read a formatted date string into its most appropriate date object.
+
+ Params:
+		fmt = date/time format
+		input = string to parse
+
+ Supported format specs are:
+
+   %d - day of month
+
+   %m - month
+
+   %y - year (4 digits)
+
+   %Y year (2 digits)
+
+   %H - hour
+
+   %h- hour (12 hour clock)
+
+   %M - minute
+
+   %S - second
+
+   %Z - Timezone
+
+   %s - Fractions of a second
+
+   %p - AM/PM (case insensitive)
+
+/
auto formattedDateTime(string fmt)(string input) {
	alias dateComponents = AliasSeq!("%d", "%m", "%y", "%Y");
	alias timeComponents = AliasSeq!("%H", "%M", "%S", "%h");
	alias timezoneComponents = AliasSeq!("%Z");
	alias fracSecComponents = AliasSeq!("%s");
	enum seq = splitSequence(fmt);
	static if (seq.canFind(timezoneComponents)) {
		Duration offset;
	}
	static if (seq.canFind(fracSecComponents)) {
		Duration fraction;
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
		int second;
		int minute;
		int hour;
	}
	static assert (seq.canFind("%h") == seq.canFind("%p"), "AM/PM (%p) and 12-hour clock (%h) must be specified together");

	static if (seq.canFind("%p")) {
		bool pmOffset;
	}

	static foreach (portion; seq) {
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
		} else static if ((portion == "%H") || (portion == "%h")) {
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
				fraction = hnsecs.hnsecs;
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
		} else static if (portion == "%p") {
			import std.string : toLower;
			assert(input.length >= 2, "Expected AM/PM, got end of string");
			auto buf = input[0..2];
			assert(buf[].toLower.among("am", "pm"), "Expected AM/PM, got "~buf);
			if (buf[].toLower == "pm") {
				pmOffset = true;
			}
		} else {
			formattedRead(input, portion);
		}
	}
	static if (seq.canFind("%p")) {
		//At 12:00AM or PM, the logic inverts.
		if (hour == 12) {
			pmOffset = !pmOffset;
		}
		hour = (hour+12*pmOffset)%24;
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
	assert(formattedDateTime!"%m-%d-%y"("03-01-94") == Date(1994, 3, 1));

	assert(formattedDateTime!"%H:%M:%S"("12:34:53") == TimeOfDay(12, 34, 53));

	assert(formattedDateTime!"%m-%d-%y %H:%M:%S"("03-01-94 12:34:53") == DateTime(Date(1994, 3, 1), TimeOfDay(12, 34, 53)));

	assert(formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 +0000") == SysTime(DateTime(Date(1994, 3, 1), TimeOfDay(12, 34, 53)), UTC()));

	assert(formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 +0100") == SysTime(DateTime(Date(1994, 3, 1), TimeOfDay(13, 34, 53)), UTC()));

	assert(formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 -0100") == SysTime(DateTime(Date(1994, 3, 1), TimeOfDay(11, 34, 53)), UTC()));

	assert(formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 +00:00") == SysTime(DateTime(Date(1994, 3, 1), TimeOfDay(12, 34, 53)), UTC()));

	assert(formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 +01:00") == SysTime(DateTime(Date(1994, 3, 1), TimeOfDay(13, 34, 53)), UTC()));

	assert(formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 -01:00") == SysTime(DateTime(Date(1994, 3, 1), TimeOfDay(11, 34, 53)), UTC()));

	assert(formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 +00") == SysTime(DateTime(Date(1994, 3, 1), TimeOfDay(12, 34, 53)), UTC()));

	assert(formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 +01") == SysTime(DateTime(Date(1994, 3, 1), TimeOfDay(13, 34, 53)), UTC()));

	assert(formattedDateTime!"%m-%d-%y %H:%M:%S %Z"("03-01-94 12:34:53 -01") == SysTime(DateTime(Date(1994, 3, 1), TimeOfDay(11, 34, 53)), UTC()));

	assert(formattedDateTime!"%Y-%m-%d %H:%M:%s"("2013-09-28 02:07:11.633883") == tuple(DateTime(2013, 9, 28, 2, 7, 11), 633_883.usecs));

	assert(formattedDateTime!"%Y-%m-%d %H:%M:%S"("2007-11-28 04:00:27") == DateTime(2007, 11, 28, 4, 0, 27));

	assert(formattedDateTime!"%Y-%m-%d %H:%M:%S"("2016-01-15 08:25:20") == DateTime(2016, 1, 15, 8, 25, 20));

	assert(formattedDateTime!"%h:%M:%S %p"("08:25:20 PM") == TimeOfDay(20, 25, 20));

	assert(formattedDateTime!"%h:%M:%S %p"("12:25:20 PM") == TimeOfDay(12, 25, 20));

	assert(formattedDateTime!"%h:%M:%S %p"("12:25:20 AM") == TimeOfDay(0, 25, 20));
}