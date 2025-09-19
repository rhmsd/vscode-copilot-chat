/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

import * as fs from 'fs';
import * as path from 'path';
import { ISimulationTestRuntime, ssuite, stest } from '../../test/base/stest';
import { fetchConversationScenarios, Scenario } from '../../test/e2e/scenarioLoader';
import { generateScenarioTestRunner } from '../../test/e2e/scenarioTest';

/**
 * Test scenario: Agent iteratively builds a C# project, fixes errors, and retries until successful
 *
 * This scenario tests the agent's ability to:
 * 1. Attempt to build a project with errors
 * 2. Read and interpret build error messages
 * 3. Fix the errors in the source code
 * 4. Retry building until successful
 * 5. Use terminal commands (dotnet build) and file editing tools
 */
ssuite({ title: 'csharp-build-fixa', subtitle: 'agent', location: 'panel' }, (inputPath) => {

	const scenarioFolder = inputPath ?? path.join(__dirname, '.');
	const scenarios: Scenario[] = fetchConversationScenarios(scenarioFolder);

	console.warn("hello csharp");

	// Dynamically create a test case per each entry in the scenarios array
	for (let i = 0; i < scenarios.length; i++) {
		const scenario = scenarios[i][0];
		stest({ description: scenario.name || 'Fix C# project build errors iteratively', language: 'csharp' },
			generateScenarioTestRunner(
				scenarios[i],
				async (accessor, question, response, fullResponse, turn, index, commands, confirmations, fileTrees) => {
					// Custom validation logic for C# build fix scenario
					console.log(`🔧 [VALIDATION-START] Processing response of length: ${fullResponse.length}`);
					console.log(`🔧 [VALIDATION-DEBUG] Response preview: ${fullResponse.substring(0, 200)}...`);

					// Define log function for consistent logging
					const log = (message: string) => {
						console.log(`🔧 ${message}`);
						try {
							const testContext = accessor.get(ISimulationTestRuntime);
							testContext.log(message);
						} catch (error) {
							// Fallback to console if test framework logging fails
						}
					};

					const expectedBehaviors = [
						// Should attempt to build the project first
						(response: string) => {
							return response.includes('dotnet build') || response.includes('building') || response.includes('compile');
						},

						// Should use run_in_terminal tool to execute build command
						(response: string) => {
							return response.includes('run_in_terminal') || response.includes('terminal');
						},

						// Should read and analyze error messages
						(response: string) => {
							return response.includes('error') && (response.includes('CS') || response.includes('build'));
						},

						// Should edit source files to fix errors
						(response: string) => {
							return response.includes('replace_string_in_file') || response.includes('edit') || response.includes('fix');
						},

						// Should retry building after fixes
						(response: string) => {
							return response.includes('build') && response.includes('again');
						}
					];

					// Check if at least some of the expected behaviors are present
					const behaviorMatches = expectedBehaviors.filter(behavior => behavior(fullResponse));
					const success = behaviorMatches.length >= 2; // At least 2 behaviors should match

					// Log detailed analysis using test framework logging
					log(`[BEHAVIOR-ANALYSIS] Found ${behaviorMatches.length}/${expectedBehaviors.length} expected behaviors`);
					log(`[BEHAVIOR-ANALYSIS] Success: ${success}`);

					// Log which specific behaviors were found
					expectedBehaviors.forEach((behavior, index) => {
						const found = behavior(fullResponse);
						const behaviorNames = [
							'dotnet build command',
							'run_in_terminal usage',
							'error analysis',
							'file editing',
							'retry building'
						];
						log(`[BEHAVIOR-CHECK] ${behaviorNames[index]}: ${found ? '✅' : '❌'}`);
					});

					// Log tool calls found in response
					const toolCallMatches = fullResponse.match(/(\w+_\w+|\w+)\(/g) || [];
					log(`[TOOL-CALLS] Found tool calls: ${toolCallMatches.join(', ')}`);

					// Write detailed analysis to file for later inspection
					const logData = {
						timestamp: new Date().toISOString(),
						responseLength: fullResponse.length,
						behaviorMatches: behaviorMatches.length,
						totalBehaviors: expectedBehaviors.length,
						success: success,
						toolCalls: toolCallMatches,
						responsePreview: fullResponse.substring(0, 500),
						fullResponse: fullResponse // Include full response for debugging
					};

					const logFile = path.join(__dirname, 'debug-analysis.json');
					try {
						fs.writeFileSync(logFile, JSON.stringify(logData, null, 2));
						log(`[FILE-OUTPUT] Analysis written to: ${logFile}`);
					} catch (error) {
						log(`[FILE-OUTPUT] Failed to write log: ${error}`);
					}

					return {
						success,
						errorMessage: success ? undefined : `Expected agent to demonstrate C# build-fix behaviors, but only ${behaviorMatches.length} out of ${expectedBehaviors.length} behaviors were found`
					};
				}
			)
		);
	}
});

console.log("hello csharp");