{
  description = "My personal project templates";

  outputs = {self}: {
    templates = {
      dioxus = {
        path = ./dioxus;
        description = "Dioxus Rust template";
      };

      bevy = {
        path = ./bevy;
        description = "Bevy Rust template";
      };

      rust = {
        path = ./rust;
        description = "Rust template";
      };
    };
  };
}
