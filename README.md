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

## Graph Nodes
Each graph node contains information on each class, and how they relate to other classes.
<img width="131" height="354" alt="Screenshot 2026-05-08 at 12 06 11 pm" src="https://github.com/user-attachments/assets/587b3943-426b-4544-b45c-b932b62b90fa" />

Graph nodes include information about a class':
* Autoload status (Graph node will be colored separately if the class is an autoload, yellow by default)
* Name (Clicking this will select the graph node, and show the path of inheritance with a separate color, pink by default)
* Following generation children count
* Variables
* Static functions
* Instance functions
* Override Functions
* TODOs

Clicking any item in a graph node dropdown with the Script window open will go to the specific line where the item is defined.

## Connections
Opening a function dropdown shows the selected class' outgoing function calls (green by default), and which other classes are calling the selected classes functions (blue by default). By viewing this, it is possible to better track how classes interact with each other.
<img width="544" height="541" alt="Screenshot 2026-05-08 at 1 19 53 pm" src="https://github.com/user-attachments/assets/676e023e-ee86-4075-b05b-2bfb0498394e" />

NOTE: The Project Mapper does not track function calls within a class.

# View settings
Finally, `project_mapper_settings.tres` contains settings you can use to control how you want the project to look. This includes various color and style options.
<img width="385" height="604" alt="Screenshot 2026-05-08 at 11 01 35 am" src="https://github.com/user-attachments/assets/9f6653f5-8a41-40ce-a832-89bee0700fd9" />

# License
MIT License. See `LICENSE` for details.
