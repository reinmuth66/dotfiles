{ ... }:

{
  programs.bottom = {
    enable = true;
    settings = {
      flags = {
        default_widget_type = "proc";
        default_widget_count = 1;
      };
      processes = {
        default_tree = true;
        default_memory_value = true;
        default_sort = "Mem%";
        columns = [
          "PID"
          "Name"
          "CPU%"
          "Mem%"
          "Time"
          "R/s"
          "W/s"
          "T.Read"
          "T.Write"
          "User"
          "State"
        ];
      };
    };
  };
}
