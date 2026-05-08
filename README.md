# Project Mapper
Project Mapper is a plugin for Godot 4.6+ that maps an entire codebase, and draws a graph showing the inheritances between parents and children.
<img width="739" height="416" alt="Screenshot 2026-05-05 at 4 56 45 pm" src="https://github.com/user-attachments/assets/5dad671f-c673-4866-a069-cce0d2c38df0" />


# Features
The Project Mapper plugin scans your entire project codebase, then visualises the inheritance between classes in a graph format. This graph format shows information on every class, including their variables, static functions, instance functions, override functions and TODOs. Additionally, the graph view shows function calls between classes. The window reacts automatically when the editor is saved.

# Installation
1. Copy `addons/project_mapper/` into your project's `addons/` folder.
2. In Godot, go to **Project settings → Plugins**, and enable the **Project Mapper** plugin. This will automatically open the `Project Mapper` dock to the bottom of the Editor.

# The Project Mapper window
The `Project Mapper` window will automatically open when the plugin is enabled. It will also automatically scan the project, and organise the graph view.

## Toolbar
The top of the window contains the following controls for the graph view:
* **Reorganise Button**: Arranges all of the graph nodes.
* **Expand/Collapse All Button**: Opens the dropdowns on every graph node and reorganises the graph view.
* **Search Bar**: Highlights graph where the search query is present in the class's name or script.
* **Straight Lines Toggle**: Toggles the grpah view between straight or curved lines.
* **Sync selection Toggle**: By enablign this, graph nodes will automatically be selected if the class' file is open in the Script Editor.

## Nodes

## Connections

# View settings
Finally, `project_mapper_settings.tres` contains settings you can use to control how you want the project to look. This includes various color and style options.
<img width="385" height="604" alt="Screenshot 2026-05-08 at 11 01 35 am" src="https://github.com/user-attachments/assets/9f6653f5-8a41-40ce-a832-89bee0700fd9" />

# License
MIT License. See `LICENSE` for details.
