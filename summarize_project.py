# summarize_project.py

import os

def summarize_project(project_path=".", output_file="summary.txt"):
    """
    Summarizes all relevant files in a project directory into a single text file.
    """
    # List of directories and files to ignore
    ignore_list = {
        ".git",
        ".DS_Store",
        "__pycache__",
        ".xcodeproj",
        ".xcworkspace",
        "project.xcworkspace",
        "xcuserdata",
        "DerivedData",
        "build",
        "Pods",
        "Carthage",
        ".build",
        output_file # Don't include the summary file itself
    }

    # List of file extensions to include (add any others you need)
    include_extensions = {
        ".swift",
        ".storyboard",
        ".xib",
        ".json",
        ".plist",
        ".entitlements",
        ".xcstrings"
    }

    try:
        with open(output_file, "w", encoding="utf-8") as summary:
            summary.write(f"Project Summary for: {os.path.abspath(project_path)}\n")
            summary.write("=" * 80 + "\n\n")

            for root, dirs, files in os.walk(project_path, topdown=True):
                # Exclude directories from the ignore list
                dirs[:] = [d for d in dirs if d not in ignore_list]

                for file in files:
                    file_path = os.path.join(root, file)
                    
                    # Check if the file should be ignored
                    if any(part in ignore_list for part in file_path.split(os.sep)):
                        continue
                        
                    # Check if the file has an included extension
                    if os.path.splitext(file)[1] in include_extensions:
                        relative_path = os.path.relpath(file_path, project_path)
                        
                        header = f"--- FILE: {relative_path} ---\n"
                        print(f"Adding: {relative_path}")

                        summary.write(header)
                        
                        try:
                            with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                                summary.write(f.read())
                            summary.write("\n\n" + "=" * 80 + "\n\n")
                        except Exception as e:
                            summary.write(f"Could not read file: {e}\n\n")
                            summary.write("=" * 80 + "\n\n")

        print(f"\n✅ Success! Project summary saved to '{output_file}'")

    except Exception as e:
        print(f"❌ An error occurred: {e}")

if __name__ == "__main__":
    summarize_project()