function [A, S, time] = mvcnmf(X, Ainit, Sinit, Atrue, UU, PrinComp, meanData, T, tol, maxiter, showflag, type_alg_S, type_alg_A, use_synthetic_data)

    % A,S: output solution
    % Ainit,Sinit: initial solutions
    % Atrue: true endmembers
    % UU: principle components for visualization (SVD) (optional)
    % PrinComp: principal components for calculating volme (PCA)
    % meanData: for calculating volume
    % T: annealing temprature
    % tol: tolerance for a relative stopping condition
    % maxiter: limit of iterations
    % showflag: display scatter plot (1)
    % type_alg_S: algorithms for estimating S
    % type_alg_A: algorithms for estimating A
    % use_synthetic_data: Whether using synthetic data

    A = Ainit;
    S = Sinit;

    % dimensions
    c = size(S, 1); % number of endmembers
    N = size(S, 2); % number of pixels

    % precalculation for visualization
    if use_synthetic_data == 1
        EM = UU' * Atrue; % low dimensional endmembers
        LowX = UU' * X; % low dimensional data

        E = [ones(1, c); PrinComp(:, 1:c - 1)' * (Atrue - meanData' * ones(1, c))];
        vol_t = 1 / factorial(c - 1) * abs(det(E)); % the volume of true endmembers
    end

    % PCA to calculate the volume of true EM
    vol = [];

    % calculate volume of estimated A
    C = [ones(1, c); zeros(c - 1, c)];
    B = [zeros(1, c - 1); eye(c - 1)];
    Z = C + B * (PrinComp(:, 1:c - 1)' * (A - meanData' * ones(1, c)));
    detz2 = det(Z) * det(Z);

    % one time draw
    if showflag
        startA = UU' * Ainit;
        figure(1),

        for i = 1:3

            for j = i + 1:3
                subplot(2, 2, (i - 1) * 2 + j - i),
                plot(LowX(i, 1:6:end), LowX(j, 1:6:end), 'rx');
                hold on,
                plot(startA(i, :), startA(j, :), 'bo'); %original estimateion
                plot(EM(i, :), EM(j, :), 'go', 'markerfacecolor', 'g'); %true endmember
            end

        end

    end

    % print_summary(detz2, "detz2")
    % print_summary(S, "S")
    % print_summary(B', "B.T")
    % print_summary(pinv(Z)', "np.linalg.pinv(Z).T")
    % calculate initial gradient
    gradA = A * (S * S') - X * S' + T * detz2 * PrinComp(:, 1:c - 1) * B' * pinv(Z)';
    % print_summary(gradA, "gradA")
    gradS = (A' * A) * S - A' * X;
    % print_summary(gradS, "gradS")
    initgrad = norm([gradA; gradS'], 'fro');
    fprintf('Init gradient norm %f\n', initgrad);
    % tolA = max(0.001, tol) * initgrad;
    % tolS = tolA;

    % Calculate initial objective
    % print_summary(A, "A");
    % print_summary(S, "S");
    % print_summary(X, "X");
    objhistory = 0.5 * sum(sum((X - A * S) .^ 2));
    fprintf("Initial objective: %f\n", objhistory);
    objhistory = [objhistory 0];
    Ahistory = [];

    % count the number of sucessive increase of obj
    inc = 0;
    inc0 = 0;
    % flag = 0;
    iter = 0;

    while inc < 5 && inc0 < 20
        fprintf('--- objhistory: %f\n', objhistory(end));

        % uphill or downhill
        if objhistory( end - 1) - objhistory(end) > 0.0001
            inc = 0;
        elseif objhistory(end) - objhistory(end - 1) > 50
            fprintf('Diverge after %d iterations!', iter);
            break;
        else
            disp('uphill');
            inc = inc + 1;
            inc0 = inc0 + 1;
        end

        if iter < 5
            inc = 0;
        end

        if iter == 0
            objhistory(end) = objhistory(end - 1);
        end

        % stopping condition
        % projnorm = norm([gradA(gradA < 0 | A > 0); gradS(gradS < 0 | S > 0)]);

        if iter > maxiter
            disp('Max iter reached, stopping!');
            break;
        end

        % Show progress
        E = [ones(1, c); PrinComp(:, 1:c - 1)' * (A - meanData' * ones(1, c))];
        vol_e = 1 / factorial(c - 1) * abs(det(E));
        fprintf('[%d]: %.5f\t', iter, objhistory(end));
        fprintf('Temperature: %f \t', T);

        if use_synthetic_data == 1
            fprintf('Actual Vol.: %f \t Estimated Vol.: %f\n', vol_t, vol_e);
        else
            fprintf('Estimated Vol.: %f\n', vol_e);
        end

        vol(iter + 1) = vol_e;

        % real time draw
        if showflag
            est = UU' * A;
            Ahistory = [Ahistory est];
            figure(1),

            for i = 1:3

                for j = i + 1:3
                    subplot(2, 2, (i - 1) * 2 + j - i),
                    plot(est(i, :), est(j, :), 'yo'); %estimation from nmf
                end

            end

            drawnow;
        end

        % to consider the sum-to-one constraint
        tX = [X; 20 * ones(1, N)];
        tA = [A; 20 * ones(1, c)];
        % print_summary(tX, "tX-mvc")
        % print_summary(tA, "tA-mvc")

        % find S
        switch type_alg_S

            case 1 % conjugate gradient learning

                no_iter = 50;
                S = conjugate(X, A, S, no_iter, PrinComp(:, 1:c - 1), meanData, T);

            case 2 % steepest descent

                tolS = 0.0001;
                [S, ~, ~] = steepdescent(tX, tA, S, tolS, 200, PrinComp(:, 1:c - 1), meanData, T);

                % if iterS == 1
                %     tolS = 0.1 * tolS;
                % end

        end

        % find A
        switch type_alg_A

            case 1 % conjugate gradient learning

                no_iter = 50;
                A = conjugate(X', S', A', no_iter, PrinComp(:, 1:c - 1), meanData, T);
                A = A';

            case 2 % steepest descent

                tolA = 0.0001;
                [A, ~, ~] = steepdescent(X', S', A', tolA, 100, PrinComp(:, 1:c - 1), meanData, T);
                A = A';
                % gradA = gradA';

                % if iterA == 1
                %     tolA = 0.1 * tolA;
                % end

        end

        % print_summary(A, "A-mvc")
        % print_summary(S, "S-mvc")
        % Calculate objective
        newobj = 0.5 * sum(sum((X - A * S) .^ 2));
        objhistory = [objhistory newobj];

        iter = iter + 1;

    end
end

% function print_summary(array, name)
%     disp("---------------------------")
%     fprintf('Size of %s: ', name);
%     disp(size(array));
%     fprintf('Minimum value: %.2f\n', min(array, [], 'all'));
%     fprintf('Maximum value: %.2f\n', max(array, [], 'all'));
%     fprintf('Mean value: %.2f\n', mean(array, 'all'));
%     fprintf('Standard deviation: %.2f\n\n', std(array, 0, 'all'));
%     disp("---------------------------")
% end
    