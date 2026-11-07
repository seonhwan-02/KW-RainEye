%% 코드 해설 문서의 확인 스크립트(checkNN.m)를 하나씩 별도 MATLAB 프로세스로 돌려 결과를 한 파일에 모은다.
% 사용: cd docs/코드해설/checks; matlab -batch run_checks   (또는 MATLAB 안에서 run_checks)
% 결과: check_results.txt (문서 번호별 CHECK 줄과 오류 메시지)
% 별도 프로세스로 도는 이유: 확인 스크립트마다 로컬 함수가 있어 evalc/run으로는 한 세션 안에서 못 부르고,
%   한 스크립트의 clear나 오류가 다른 스크립트에 번지지 않게 하기 위해서다.
here = fileparts(mfilename('fullpath'));
files = dir(fullfile(here, 'check*.m'));
out = fullfile(here, 'check_results.txt');
fid = fopen(out, 'w', 'n', 'UTF-8');
fprintf(fid, '코드 해설 확인 스크립트 결과  %s\n', string(datetime('now')));
for k = 1:numel(files)
    name = erase(files(k).name, '.m');
    fprintf(fid, '\n==== %s ====\n', name);  fprintf('==== %s ====\n', name);
    t0 = tic;
    cmd = sprintf('matlab -batch "cd(''%s''); %s"', here, name);
    [rc, txt] = system(cmd);
    txt = regexprep(txt, '^(오류|Error)[:：]?\s*', 'ERROR: ', 'lineanchors');
    fprintf(fid, '%s', txt);  fprintf('%s', txt);
    if rc ~= 0, fprintf(fid, 'ERROR: exit code %d\n', rc); end
    fprintf(fid, '(%.1f s)\n', toc(t0));
end
fclose(fid);
fprintf('saved %s\n', out);
