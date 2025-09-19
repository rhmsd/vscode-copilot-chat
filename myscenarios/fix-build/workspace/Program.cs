using System;

namespace HelloWorldApp
{
    class Program
    {
        static void Main(string[] args)
        {
            Console.WriteLine("Hello, World from C#!");
            Console.WriteLine("Welcome to .NET development!");

            // Intentional error: undefined variable
            Console.WriteLine($"Message: {undefinedVariable}");

            // Intentional syntax error: missing semicolon
            a x = 10
            b y = 25;
            Console1.WriteLine($"The sum of {x} and {y} is {x + y}");

            // Intentional error: wrong method name
            Console.WriteLine("Press any key to exit...");
            Console.ReadKeyInvalid();
        }
    }
}