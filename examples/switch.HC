// HolyC switch: caseless auto-increment, ranges, and sub_switch groups.
I64 i;
for (i = 0; i < 6; i++)
  switch (i) {
    case: "Zero\n"; break;   // starts at 0
    case: "One\n"; break;    // prev + 1
    case 2: "Two\n"; break;
    case 3...4: "ThreeOrFour\n"; break;
    default: "Other\n"; break;
  }

// sub_switch: start/end porch code shared by grouped cases
for (i = 0; i < 6; i++)
  switch (i) {
    case 0: "Zero "; break;
    case 2: "Two "; break;
    case 4: "Four "; break;
    start:
      "[";
      case 1: "One"; break;
      case 3: "Three"; break;
      case 5: "Five"; break;
    end:
      "] ";
      break;
  }
"\n";
