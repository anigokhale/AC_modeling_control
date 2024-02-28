function [xsegment, usegment, tsegment, Ksegment] = get_segment_traj(segArray)
MOI = segArray{1};
constants = [segArray{3}; segArray{2}; segArray{4}];
xcrit1 = segArray{5}(:, 1);
xcrit2 = segArray{5}(:, 2);
ucrit2 = segArray{6};
limits = segArray{7};
throttleConsts = segArray{9};
numPoints = segArray{10};
ti = segArray{11};
tf = segArray{12};
Qbry = segArray{13};
Rbry = segArray{14};
genOn = segArray{15};

%Get symbolic EOMS and variables
[x, u, ~, Jx, Ju, consts, Jmat] = EOMS(throttleConsts);
J1 = Jmat(1, 1);
J2 = Jmat(1, 2);
J3 = Jmat(1, 3);
J4 = Jmat(2, 1);
J5 = Jmat(2, 2);
J6 = Jmat(2, 3);
J7 = Jmat(3, 1);
J8 = Jmat(3, 2);
J9 = Jmat(3, 3);

%Calculate A matrix in state space representation
A = subs(Jx, [x; u; consts], [zeros(length(xcrit2), 1); ucrit2; constants]);
A = double(subs(A, [J1 J2 J3; J4 J5 J6; J7 J8 J9], MOI));

%Calculate B matrix in state space representation
B = subs(Ju, [x; u; consts], [zeros(length(xcrit2), 1); ucrit2; constants]);
B = double(subs(B, [J1 J2 J3; J4 J5 J6; J7 J8 J9], MOI));

%Determine lqr cost functions Q, and R
if genOn
    [Q, R] = genetic_algorithm(x, A, B, segArray);
else
    Q = diag(Qbry);
    R = diag(Rbry);
end

%Optimal control gain matrix K, solution S, and poles P
try
    [Ksegment, ~, ~] = lqr(A, B, Q, R);
catch e
    disp(e.message);
    error("LQR gain generation threw the error above!");
end
    
%Simulate using input data
%Utilizes dynamics' translational symmetry to approach critical points
[xsegment, usegment, tsegment] = simulate(ti, tf, numPoints, Ksegment, constants, MOI, xcrit1-xcrit2, limits);

% Create tracking gains for the simulation
C = [eye(3), zeros(3, length(A)-3)];
Atilde = [A, zeros(size(A, 1), 3); C, zeros(size(C, 1), 3)];
Btilde = [B; zeros(3, size(B, 2))];
Qtilde = diag([diag(Q); (.01*ones(3, 1)).^-2]);
Rtilde = R; 

[Ksegment, ~, ~] = lqr(Atilde, Btilde, Qtilde, Rtilde);

end

%Simulates and returns trajectory
function [xPlot, uPlot, tsegment, odeStopped] = simulate(ti, tf, numPoints, K, consts, MOI, xcrit, limits)
    %SIMULATE
    stopTime = 2;
    odeStopped = false;
    tsegment = linspace(ti, tf, numPoints);
    timer = tic;
    opts = odeset('RelTol', 1e-12, 'AbsTol', 1e-12, 'Events', @(t, x) time_EventsFcn(t, x, timer, stopTime)); %, 'OutputFcn', @(t, x, flag, stopTime) stopTimeFunction(t, x, flag, stopTime)
    try 
        [~, xPlot] = ode45(@(t, x) deriv(t, x, K, consts, MOI, limits), tsegment, xcrit, opts);
    catch 
        odeStopped = true;
    end

    if ~odeStopped
        xPlot = xPlot';
        
        %Create simulated control inputs
        uPlot = zeros(size(K, 1), size(tsegment, 1));
        for i = 1:size(xPlot, 2)
            uPlot(:, i) = constrain(-K*xPlot(:, i), limits);
        end
    else
        xPlot = 0;
        uPlot = 0;
        tsegment = 0;
    end
end

%Returns numerical EOMS (MUST UPDATE FROM EOMS.m WHEN EOMS ARE UPDATED)
function xdot = deriv(~, x, K, consts, MOI, limits)
    m = consts(1);
    l = consts(2);
    g = consts(3);
    J1 = MOI(1, 1);
    J2 = MOI(1, 2);
    J3 = MOI(1, 3);
    J4 = MOI(2, 1);
    J5 = MOI(2, 2);
    J6 = MOI(2, 3);
    J7 = MOI(3, 1);
    J8 = MOI(3, 2);
    J9 = MOI(3, 3);
    v1 = x(4);
    v2 = x(5);
    v3 = x(6);
    q1 = x(7);
    q2 = x(8);
    q3 = x(9);
    omega1 = x(10);
    omega2 = x(11);
    omega3 = x(12);

    u = constrain(-K * x, limits);
    beta = u(1);
    gamma = u(2);
    throttle = u(3);
    tau_RW = u(4);

    xdot = [v1; v2; v3; -(g*m - sin(beta)*(2*q1*q3 + 2*conj(sqrt(- q1^2 - q2^2 - q3^2 + 1))*q2)*((7*throttle^3)/62500 - (259*throttle^2)/12500 + (67*throttle)/250) - cos(beta)*cos(gamma)*(2*(q2)^2 + 2*(q3)^2 - 1)*((7*throttle^3)/62500 - (259*throttle^2)/12500 + (67*throttle)/250) + cos(beta)*sin(gamma)*(2*q1*q2 - 2*conj(sqrt(- q1^2 - q2^2 - q3^2 + 1))*q3)*((7*throttle^3)/62500 - (259*throttle^2)/12500 + (67*throttle)/250))/m; (sin(beta)*(2*q2*q3 - 2*conj(sqrt(- q1^2 - q2^2 - q3^2 + 1))*q1)*((7*throttle^3)/62500 - (259*throttle^2)/12500 + (67*throttle)/250) + cos(beta)*sin(gamma)*(2*(q1)^2 + 2*(q3)^2 - 1)*((7*throttle^3)/62500 - (259*throttle^2)/12500 + (67*throttle)/250) - cos(beta)*cos(gamma)*(2*q1*q2 + 2*conj(sqrt(- q1^2 - q2^2 - q3^2 + 1))*q3)*((7*throttle^3)/62500 - (259*throttle^2)/12500 + (67*throttle)/250))/m; -(sin(beta)*(2*(q1)^2 + 2*(q2)^2 - 1)*((7*throttle^3)/62500 - (259*throttle^2)/12500 + (67*throttle)/250) + cos(beta)*cos(gamma)*(2*q1*q3 - 2*conj(sqrt(- q1^2 - q2^2 - q3^2 + 1))*q2)*((7*throttle^3)/62500 - (259*throttle^2)/12500 + (67*throttle)/250) + cos(beta)*sin(gamma)*(2*q2*q3 + 2*conj(sqrt(- q1^2 - q2^2 - q3^2 + 1))*q1)*((7*throttle^3)/62500 - (259*throttle^2)/12500 + (67*throttle)/250))/m; (omega1*sqrt(- q1^2 - q2^2 - q3^2 + 1))/2 - (omega2*q3)/2 + (omega3*q2)/2; (omega2*sqrt(- q1^2 - q2^2 - q3^2 + 1))/2 + (omega1*q3)/2 - (omega3*q1)/2; (omega3*sqrt(- q1^2 - q2^2 - q3^2 + 1))/2 - (omega1*q2)/2 + (omega2*q1)/2; (62500*J2^2*J6*omega2^2 + 62500*J2^2*J9*omega2*omega3 - 62500*J2*J3*J5*omega2^2 + 62500*J2*J3*J6*omega2*omega3 - 62500*J2*J3*J8*omega2*omega3 + 62500*J2*J3*J9*omega3^2 - 62500*J2*J5*J6*omega1*omega2 - 62500*J2*J6^2*omega1*omega3 - 62500*J4*J2*J6*omega1^2 + 62500*J1*J2*J6*omega1*omega2 + 7*l*cos(beta)*sin(gamma)*J2*J6*throttle^3 - 1295*l*cos(beta)*sin(gamma)*J2*J6*throttle^2 + 16750*l*cos(beta)*sin(gamma)*J2*J6*throttle - 62500*J2*J8*J9*omega1*omega2 - 62500*J2*J9^2*omega1*omega3 - 62500*J7*J2*J9*omega1^2 + 62500*J1*J2*J9*omega1*omega3 - 7*l*sin(beta)*J2*J9*throttle^3 + 1295*l*sin(beta)*J2*J9*throttle^2 - 16750*l*sin(beta)*J2*J9*throttle - 62500*J3^2*J5*omega2*omega3 - 62500*J3^2*J8*omega3^2 + 62500*J3*J5^2*omega1*omega2 + 62500*J3*J5*J6*omega1*omega3 + 62500*J4*J3*J5*omega1^2 - 62500*J1*J3*J5*omega1*omega2 - 7*l*cos(beta)*sin(gamma)*J3*J5*throttle^3 + 1295*l*cos(beta)*sin(gamma)*J3*J5*throttle^2 - 16750*l*cos(beta)*sin(gamma)*J3*J5*throttle + 62500*J3*J8^2*omega1*omega2 + 62500*J3*J8*J9*omega1*omega3 + 62500*J7*J3*J8*omega1^2 - 62500*J1*J3*J8*omega1*omega3 + 7*l*sin(beta)*J3*J8*throttle^3 - 1295*l*sin(beta)*J3*J8*throttle^2 + 16750*l*sin(beta)*J3*J8*throttle + 62500*J5^2*J9*omega2*omega3 - 62500*J5*J6*J8*omega2*omega3 + 62500*J5*J6*J9*omega3^2 - 62500*J5*J8*J9*omega2^2 - 62500*J5*J9^2*omega2*omega3 - 62500*J7*J5*J9*omega1*omega2 + 62500*J4*J5*J9*omega1*omega3 + 62500*tau_RW*J5*J9 - 62500*J6^2*J8*omega3^2 + 62500*J6*J8^2*omega2^2 + 62500*J6*J8*J9*omega2*omega3 + 62500*J7*J6*J8*omega1*omega2 - 62500*J4*J6*J8*omega1*omega3 - 62500*tau_RW*J6*J8)/(62500*(J1*J5*J9 - J1*J6*J8 - J2*J4*J9 + J2*J6*J7 + J3*J4*J8 - J3*J5*J7)); -(62500*J1^2*J6*omega1*omega2 + 62500*J1^2*J9*omega1*omega3 - 62500*J1*J3*J4*omega1*omega2 + 62500*J1*J3*J6*omega2*omega3 - 62500*J1*J3*J7*omega1*omega3 + 62500*J1*J3*J9*omega3^2 - 62500*J1*J4*J6*omega1^2 - 62500*J1*J6^2*omega1*omega3 - 62500*J5*J1*J6*omega1*omega2 + 62500*J2*J1*J6*omega2^2 + 7*l*cos(beta)*sin(gamma)*J1*J6*throttle^3 - 1295*l*cos(beta)*sin(gamma)*J1*J6*throttle^2 + 16750*l*cos(beta)*sin(gamma)*J1*J6*throttle - 62500*J1*J7*J9*omega1^2 - 62500*J1*J9^2*omega1*omega3 - 62500*J8*J1*J9*omega1*omega2 + 62500*J2*J1*J9*omega2*omega3 - 7*l*sin(beta)*J1*J9*throttle^3 + 1295*l*sin(beta)*J1*J9*throttle^2 - 16750*l*sin(beta)*J1*J9*throttle - 62500*J3^2*J4*omega2*omega3 - 62500*J3^2*J7*omega3^2 + 62500*J3*J4^2*omega1^2 + 62500*J3*J4*J6*omega1*omega3 + 62500*J5*J3*J4*omega1*omega2 - 62500*J2*J3*J4*omega2^2 - 7*l*cos(beta)*sin(gamma)*J3*J4*throttle^3 + 1295*l*cos(beta)*sin(gamma)*J3*J4*throttle^2 - 16750*l*cos(beta)*sin(gamma)*J3*J4*throttle + 62500*J3*J7^2*omega1^2 + 62500*J3*J7*J9*omega1*omega3 + 62500*J8*J3*J7*omega1*omega2 - 62500*J2*J3*J7*omega2*omega3 + 7*l*sin(beta)*J3*J7*throttle^3 - 1295*l*sin(beta)*J3*J7*throttle^2 + 16750*l*sin(beta)*J3*J7*throttle + 62500*J4^2*J9*omega1*omega3 - 62500*J4*J6*J7*omega1*omega3 + 62500*J4*J6*J9*omega3^2 - 62500*J4*J7*J9*omega1*omega2 - 62500*J4*J9^2*omega2*omega3 - 62500*J8*J4*J9*omega2^2 + 62500*J5*J4*J9*omega2*omega3 + 62500*tau_RW*J4*J9 - 62500*J6^2*J7*omega3^2 + 62500*J6*J7^2*omega1*omega2 + 62500*J6*J7*J9*omega2*omega3 + 62500*J8*J6*J7*omega2^2 - 62500*J5*J6*J7*omega2*omega3 - 62500*tau_RW*J6*J7)/(62500*(J1*J5*J9 - J1*J6*J8 - J2*J4*J9 + J2*J6*J7 + J3*J4*J8 - J3*J5*J7)); (62500*J1^2*J5*omega1*omega2 + 62500*J1^2*J8*omega1*omega3 - 62500*J1*J2*J4*omega1*omega2 + 62500*J1*J2*J5*omega2^2 - 62500*J1*J2*J7*omega1*omega3 + 62500*J1*J2*J8*omega2*omega3 - 62500*J1*J4*J5*omega1^2 - 62500*J1*J5^2*omega1*omega2 - 62500*J6*J1*J5*omega1*omega3 + 62500*J3*J1*J5*omega2*omega3 + 7*l*cos(beta)*sin(gamma)*J1*J5*throttle^3 - 1295*l*cos(beta)*sin(gamma)*J1*J5*throttle^2 + 16750*l*cos(beta)*sin(gamma)*J1*J5*throttle - 62500*J1*J7*J8*omega1^2 - 62500*J1*J8^2*omega1*omega2 - 62500*J9*J1*J8*omega1*omega3 + 62500*J3*J1*J8*omega3^2 - 7*l*sin(beta)*J1*J8*throttle^3 + 1295*l*sin(beta)*J1*J8*throttle^2 - 16750*l*sin(beta)*J1*J8*throttle - 62500*J2^2*J4*omega2^2 - 62500*J2^2*J7*omega2*omega3 + 62500*J2*J4^2*omega1^2 + 62500*J2*J4*J5*omega1*omega2 + 62500*J6*J2*J4*omega1*omega3 - 62500*J3*J2*J4*omega2*omega3 - 7*l*cos(beta)*sin(gamma)*J2*J4*throttle^3 + 1295*l*cos(beta)*sin(gamma)*J2*J4*throttle^2 - 16750*l*cos(beta)*sin(gamma)*J2*J4*throttle + 62500*J2*J7^2*omega1^2 + 62500*J2*J7*J8*omega1*omega2 + 62500*J9*J2*J7*omega1*omega3 - 62500*J3*J2*J7*omega3^2 + 7*l*sin(beta)*J2*J7*throttle^3 - 1295*l*sin(beta)*J2*J7*throttle^2 + 16750*l*sin(beta)*J2*J7*throttle + 62500*J4^2*J8*omega1*omega3 - 62500*J4*J5*J7*omega1*omega3 + 62500*J4*J5*J8*omega2*omega3 - 62500*J4*J7*J8*omega1*omega2 - 62500*J4*J8^2*omega2^2 - 62500*J9*J4*J8*omega2*omega3 + 62500*J6*J4*J8*omega3^2 + 62500*tau_RW*J4*J8 - 62500*J5^2*J7*omega2*omega3 + 62500*J5*J7^2*omega1*omega2 + 62500*J5*J7*J8*omega2^2 + 62500*J9*J5*J7*omega2*omega3 - 62500*J6*J5*J7*omega3^2 - 62500*tau_RW*J5*J7)/(62500*(J1*J5*J9 - J1*J6*J8 - J2*J4*J9 + J2*J6*J7 + J3*J4*J8 - J3*J5*J7))];
end

%Constrains input to limits
function unew = constrain(u, limits)
    unew = zeros(size(u, 1), size(u, 2));
    
    beta_min = limits(1, 1);
    beta_max = limits(1, 2);
    if u(1) > beta_max
        unew(1) = beta_max;
    elseif u(1) < beta_min
        unew(1) = beta_min;
    else
        unew(1) = u(1);
    end
    
    gamma_min = limits(2, 1);
    gamma_max = limits(2, 2);
    if u(2) > gamma_max
        unew(2) = gamma_max;
    elseif u(2) < gamma_min
        unew(2) = gamma_min;
    else
        unew(2) = u(2);
    end

    T_min = limits(3, 1);
    T_max = limits(3, 2);

    if u(3) > T_max
        unew(3) = T_max;
    elseif u(3) < T_min
        unew(3) = T_min;
    else
        unew(3) = u(3);
    end
    
    tau_min = limits(4, 1);
    tau_max = limits(4, 2);
    if u(4) > tau_max
        unew(4) = tau_max;
    elseif u(4) < tau_min
        unew(4) = tau_min;
    else
        unew(4) = u(4);
    end
end

function [value,isterminal,direction] = time_EventsFcn(~, ~, timer, stopTime) 
    value = 1; % The value that we want to be zero 
    if stopTime - toc(timer) < 0 % Halt if he has not finished in 3     
        error("ODE45:runtimeEvent", "Integration stopped: time longer than %f seconds", stopTime)
    end 
    isterminal = 1;  % Halt integration  
    direction = 0; % The zero can be approached from either direction 
end

function [Q, R] = genetic_algorithm(x, A, B, segArray)
% GENETIC_ALGORITHM
%   Unique Inputs: popSize = initial population size
%                  mut_rate1 = initial mutation rate
%                  mut_rate2 = final mutation rate
%                      - mutation rate decreases on a power scale from 
%                        mut_rate1 to mut_rate2 as the population decreases
%                  gen_cut = cuttoff point for general population
%                  elite_cut = cuttoff point for elite population (top 1 
%                              solution will always be preserved regardless
%                              of the cuttoff rate)
%
%   General Info: The genetic algorithm has X stages. First, an initial 
%                 population is generated using Bryson's Rule as a basis
%                 then performing mutation and crossover on all but one 
%                 solution to create variation. Second, the dynamics of the
%                 system are modeled in order to evaluate fitness. Third,
%                 the population undergoes the culling/reproduction stage.
%                 The top gen_cut solutions are kept and undergo mutation
%                 and crossover with eachother. The top elite_cut solutions
%                 do not undergo mutation or crossover with any other
%                 solutions.
MOI = segArray{1};
constants = [segArray{3}; segArray{2}; segArray{4}];
xcrit1 = segArray{5}(:, 1);
xcrit2 = segArray{5}(:, 2);
limits = segArray{7};
numPoints = segArray{10};
ti = segArray{11};
tf = segArray{12};
Qbry = segArray{13};
Rbry = segArray{14};

solns = population;
solns.popSize = segArray{16};
solns.allele_seed = [Qbry;Rbry];
solns.mut_rate1 = segArray{17};
solns.mut_rate2 = segArray{18};
solns.gen_cut = segArray{19};
solns.elite_cut = segArray{20};

% Gen initial pop
%solns = [Qbry; Rbry] .* ones(1, popSize);
%solns(:, 2:end) = mutate(solns(:, 2:end), mut_rate2 + ((mut_rate1 - mut_rate2)/2^popSize)*2^size(solns, 2), [Qbry; Rbry]); % Mutation rate starts at 0.5 and decreases along a power curve as population size decreases
%solns(:, 2:end) = crossover(solns(:, 2:end)); % Preserve one genome from bryson's rule

solns.generate_genes()
solns.reproduce()

fprintf("Genetic Algorithm...\n")
while size(solns, 2) > 1
    fprintf("PopSize = %d\n", size(solns,2))
    fit = -1 * ones(1, size(solns, 2));

    % Simulate dynamics for each solution
    parfor i = 1:size(solns,2)
        lqrFail = false;
        Q = diag(solns(1:size(x,1), i));
        R = diag(solns(size(x,1) + 1:end, i));
        %Optimal control gain matrix K, solution S, and poles P
        try
            [Ksegment, ~, ~] = lqr(A, B, Q, R);
        catch
            fprintf("LQR Fail\n")
            lqrFail = true;
        end

        if ~lqrFail
            %Simulate using input data
            %Utilizes dynamics' translational symmetry to approach critical points
            [xsegment, ~, ~, odeStopped] = simulate(ti, tf, numPoints, Ksegment, constants, MOI, xcrit1-xcrit2, limits); 
    
            % Evaluate fitness
            if odeStopped 
                fprintf("ODE Stopped\n")
            
            elseif constraintCheck(xsegment, segArray) == False %make this compatible withe the 12x2 logical array output from constraintCheck
                fprintf("Constraint Check FAILED")

            else
                fit(i) = cost_function(xsegment, segArray);
                fprintf("Solution SUCCESSFUL!\n")
            end
        end
    end

    % Reproduction
    if size(solns, 2) > 1
        clear I_fit
        [fit, I_fit] = maxk(fit, floorDiv(size(solns, 2), gen_cut^-1));
        solns = solns(:, I_fit);
        fprintf("Max Fit: %f\n", fit(1))

        % Mutation and Crossover (Employ elitism to ensure fitness of pop doesnt decrease
        if elite_cut > 0
            I_elite = max(1, floorDiv(size(solns,2), elite_cut^-1));
        else
            I_elite = 1;
        end
        solns(:, I_elite + 1:end) = mutate(solns(:, I_elite + 1:end), mut_rate_eq(mut_rate1, mut_rate2, popSize, solns), [Qbry; Rbry]);
        solns(:, I_elite + 1:end) = crossover(solns(:, I_elite + 1:end));
    end
end

Q = diag(solns(1:size(x,1), 1));
R = diag(solns(size(x,1) + 1:end, 1));
end

function solns_cross = crossover(solns)
%CROSSOVER Summary of this function goes here
%   Performs crossover on genetic algorithm solution set

solns_cross = solns;

for i = 1:size(solns,2) - 1
    p1 = randi(size(solns,1));
    p2 = randi(size(solns,1));
    solns_cross(p1:p2, i) = solns(p1:p2, i+1);
    solns_cross(p1:p2, i+1) = solns(p1:p2, i);

end
end

function solns_mut = mutate(solns, mut_rate, seed)
% MUTATE applies random mutation to solution set of genetic algorithm
%   Performs mutation on genetic algorithm solution set

maxVal = seed * 1e+04;
minVal = 1.0e-08;
sigma = (maxVal - minVal)/6;

solns_mut = zeros(size(solns));
for i = 1:size(solns, 2)
    for j = 1:size(solns,1)
        if rand < mut_rate % mutations have ~mut_rate*100 % chance of occuring
            solns_mut(j,i) = solns(j,i) + sigma(j)*randn;
            solns_mut(j,i) = min(solns_mut(j,i), maxVal(j));
        else
            solns_mut(j,i) = solns(j,i);
        end
    end
end

solns_mut(solns_mut < minVal) = minVal;
end

function mut_rate = mut_rate_eq(mut_rate1, mut_rate2, popSize, solns)
%MUTE_RATE
%   Used to implement a dynamic mutation rate that changes with population
%   size
    mut_rate = mut_rate2 + ((mut_rate1 - mut_rate2)/2^popSize)*2^size(solns, 2);
end

function constCheck = constraintCheck(xsegment, segArray)
%CONSTRAINT CHECK
%   Checks against constraint array to ensure solution meats pre-defined 
%   constraints.
    stateLimits = segArray{8};

    %check against state limits
    minCheck = xsegment > stateLimits(:, 1);
    maxCheck = xsegment < stateLimits(:, 2);

    % account for states with no limits (isnan is a logical array with a 1 
    % for any NaN in the passed array so adding it to constCheck will make 
    % all states with no limit true
    constCheck = [minCheck, maxCheck] + isnan(stateLimits);

end

function fitness = cost_function(xsegment, segArray)
%COST_FUNCTION
%   Evaluates fitness of genetic algorithm solution based on state
%   information from simulation and reference critical value. Also cross
%   checks state information with state min and state max vectors from
%   parameter cell array.

    xcrit2 = segArray{5}(:, 2);
    weights = segArray{21};
    
    %evaluate fitness of solution
    zsegment = xcrit2 - xsegment;
    OS = max(abs(zsegment), [], 2);
    FE = abs(zsegment(:,end));
    fitness = 1/(weights(1) * (OS(1) + OS(2) + OS(3)) + weights(2)*(FE(1) + FE(2) + FE(3)));
end