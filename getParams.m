clear;
%Get constants from PDM integration
addpath('lib\');
addpath('PDM_integration\');
raw = readmatrix("/parameters.xlsx");
MOI = raw(1:3, 2:4);
l = raw(4, 2);
m = raw(5, 2);
g = 9.81;

%Enumerate operating points for trajectory below:
initEul = [pi/2, pi/6, pi/3];
q1 = angle2quat(initEul(1), initEul(2), initEul(3), 'XYZ')';
q1 = q1(2:end);
x1 = [10; 10; 10; 0; 0; 0; q1; 0; 0; 0];
u1 = [0; 0; m*g; 0];

q2 = angle2quat(0, 0, 0, 'XYZ')';
q2 = q2(2:end);
x2 = [5; 5; 5; 0; 0; 0; q2; 0; 0; 0];
u2 = [0; 0; m*g; 0];

q3 = angle2quat(0, 0, 0, 'XYZ')';
q3 = q3(2:end);
x3 = [1; 0; 0; 0; 0; 0; q3; 0; 0; 0];
u3 = [0; 0; m*g; 0];

%Maximum and minimum values for input for simulation
inputLimits = [-pi/12, pi/12; -pi/12, pi/12; 0, 100; -2, 2];

%Throttle -> Thrust force equation constants
throttleConsts = [-0.000112; 0.02072; -.268];

%Delay for servo angle inputs
betaInputDelay = 0.001;
gammaInputDelay = 0.001;

%SIMULATE and create trajectory
fprintf("Creating Trajectory\n");

time = 200;
[x_set, u_set, t_set, Kset, tSegs, startTime, stopTime] = get_trajectory(10000, time, [x1, x2, x3], [u1, u2, u3], [m; l; g], MOI, inputLimits, throttleConsts);

disp('plotting trajectory')
plotTrajectory(x_set, u_set, t_set, 0.75, 500, [m; l; g]);

fprintf("Done initializing!\n");