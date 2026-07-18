// Returning from global startup sets the hosted process status.  Exit remains
// available when a nested path must terminate immediately.
if (argc)
  Exit(23);
return 37;
