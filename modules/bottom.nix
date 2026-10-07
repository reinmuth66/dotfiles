{ ... }:

{
  programs.bottom = {
    enable = true;
    settings = {
      flags = {
        default_widget_type = "proc";
        default_widget_count = 1;
        hide_time = true;
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
          "User"
          "State"
        ];
      };
      row = [
        {
          child = [
            {
              child = [
                { type = "cpu"; }
                { type = "mem"; }
                { type = "net"; }
              ];
            }
            {
              child = [
                {
                  ratio = 1;
                  type = "disk";
                }
                {
                  ratio = 13;
                  type = "proc";
                  default = true;
                }
              ];
            }
          ];
        }
      ];
      cpu.default = "avg";
      disk.mount_filter = {
        is_list_ignored = false;
        list = [ "/" ];
        regex = true;
        whole_word = true;
      };
    };
  };
}
